import Foundation
import Vapor
import NIOConcurrencyHelpers


fileprivate extension String {
    var fileExt: String {
        if let i = lastIndex(of: ".") { return String(self[index(after: i)..<endIndex]) }
        return ""
    }
}

/// Serves files from a public directory, interpreting as templates if the file is such.
public final class FileTemplateMiddleware: Middleware {

    @RuntimeGuard
    public static var defaultMediaType: HTTPMediaType = .html
    
    @RuntimeGuard
    public static var processableExtensions: Set<String> = [TemplateSources.defaultExtension, "html"]
    
    @RuntimeGuard(condition: {$0.valid})
    public static var directoryIndexing: DirectoryIndexing = .prohibit
    
    /// Creates a new instance - validates that the configured path is an existing directory.
    public init?(publicDirectory dir: String) {
        var dir = dir
        if !dir.hasSuffix("/") { dir.append("/") }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir),
              isDir.boolValue else { return nil }
        self.dir = dir
        self.scope = "_LFM\(dir.hashValue)"
    }
    
    /// Behavior when the requested file is a directory.
    ///
    /// If file handling behavior is set and no such file exists, will fallback to `.prohibit`
    public enum DirectoryIndexing: Hashable {
        /// Disallow any access to directories
        case prohibit
        /// Ignore access to directories - pass to next responder
        case ignore
        /// Handle via a file  - always relative to the requested directory, must be immediately inside it.
        case relative(String)
        /// Handle all indexing via a single file. Never relative to the requested directory - can be absolutely
        /// pathed, or relative to the instance's configured directory.
        case absolute(String)
        
        @RuntimeGuard
        public static var keys: [URLResourceKey] = [
            .nameKey, .canonicalPathKey, .fileSizeKey,
            .creationDateKey, .contentModificationDateKey,
            .isApplicationKey, .isDirectoryKey, .isRegularFileKey,
            .isHiddenKey, .isSymbolicLinkKey
        ]
        
        @RuntimeGuard
        public static var options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants
        ]
    }
    
    private static let lock: Lock = .init()
    private static var lookup: [String: (process: Bool, modTime: Date)] = [:]
    private static var _contexts: [HTTPMediaType: Renderer.Context] = [:]
    
    /// Raw directory path is mangled into a source key
    private let dir: String
    private let scope: String
}

public extension FileTemplateMiddleware {
    /// The context associated with `defaultMediaType`
    static var defaultContext: Renderer.Context? {
        get { self[defaultMediaType] }
        set { self[defaultMediaType] = newValue }
    }
    
    /// All media-type-specific contexts
    static var contexts: [HTTPMediaType: Renderer.Context] {
        get { lock.withLock { _contexts } }
        set { lock.withLockVoid { _contexts = newValue } }
    }
    
    static subscript(context: HTTPMediaType) -> Renderer.Context? {
        get { lock.withLock { _contexts[context] ?? .emptyContext() } }
        set { lock.withLockVoid { _contexts[context] = newValue } }
    }
    
    func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        var chain: EventLoopFuture<Response> { next.respond(to: request) }
                
        /// Fully qualify path
        var path = URL(fileURLWithPath: dir + (request.url.path.removingPercentEncoding ?? ""))
                      .standardizedFileURL.path
        guard !path.isEmpty, (path.count + 1) >= dir.count else { return request.eventLoop.future(error: badRequest) }
        
        /// Validate it exists and add trailing slash if it's a directory
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) { return chain }
        if isDir.boolValue { path += "/" }
        
        /// Handle state if it's a directory
        let directoryIndex = path.hasSuffix("/")
        /// Cache directory path if it's for indexing
        let directory = directoryIndex ? path : ""
        if directoryIndex {
            switch indexing {
                case .ignore          : return chain
                case .prohibit        : return request.eventLoop.future(error: noDirIndex)
                case .relative(let p) : path += p
                case .absolute(let p) :
                    if p.hasPrefix("/") { path = p}
                    else { path = dir + p }
                    path = URL(fileURLWithPath: path).standardizedFileURL.path
            }
            
            /// At this point, `path` represents a concrete indexing file - if it doesn't exist, fail
            if !FileManager.default.fileExists(atPath: path) { return request.eventLoop.future(error: noDirIndex) }
        }
        
        /// Non-processable extension immediately streams
        if !Self.processableExtensions.contains(path.fileExt) { return stream(path, on: request) }
        
        var record = self[path] ?? (false, .distantPast)
                
        guard let attr = try? FileManager.default.attributesOfItem(atPath: path),
              let modTime = attr[.modificationDate] as? Date else { return request.eventLoop.future(error: moduleError) }
        
        /// Only check actual file contents if mod time isn't the recorded state
        if modTime != record.modTime {
            record.modTime = modTime
            let fileio = request.application.fileio
            let eL = request.eventLoop
            
            return fileio.openFile(path: path, eventLoop: request.eventLoop)
                .flatMap { file in
                    fileio.read(fileRegion: file.1, allocator: ByteBufferAllocator(), eventLoop: eL)
                        .flatMapThrowing { buffer -> ByteBuffer in
                            try file.0.close()
                            return buffer }
                        .flatMap {
                            var buffer = $0
                            let src = buffer.readString(length: buffer.readableBytes) ?? ""
                            // FIXME: process check is blocking
                            record.process = TemplateEngine.entities.validate(in: src) != false
                            self[path] = record
                            if directoryIndex && record.process { self.contextualize(directory, on: request) }
                            return record.process ? self.process(path, on: request, update: true)
                                                  : self.stream(path, on: request)
                        }
                }
        }
        
        if directoryIndex && record.process { contextualize(directory, on: request) }
        return record.process ? process(path, on: request) : stream(path, on: request)
    }
}

private extension FileTemplateMiddleware {
    var notFound: Abort { Abort(.notFound) }
    var forbidden: Abort { Abort(.forbidden) }
    var badRequest: Abort { Abort(.badRequest) }
    var noDirIndex: Abort { Abort(.forbidden, reason: "Directory indexing disallowed") }
    var noRelative: Abort { Abort(.forbidden, reason: "Relative paths disallowed") }
    var moduleError: Abort { Abort(.internalServerError, reason: "FileTemplateMiddleware internal error") }
        
    subscript(path: String) -> (process: Bool, modTime: Date)? {
        get { Self.lock.withLock { Self.lookup[path] } }
        set { Self.lock.withLockVoid { Self.lookup[path] = newValue } }
    }
    
    subscript(context: HTTPMediaType) -> Renderer.Context? {
        get { Self[context] }
        set { Self[context] = newValue }
    }
    
    var indexing: FileTemplateMiddleware.DirectoryIndexing { Self.directoryIndexing }
    
    /// Process as template file.
    func process(_ path: String, on req: Request, update: Bool = false) -> EventLoopFuture<Response> {
        /// Ensure source for this directory is set up, fail if it isn't.
        if let failure = checkSource(req) { return failure }
        
        /// Strip path to the relative portion
        var relative = path
        relative.removeFirst(dir.count)
        
        let contentType = HTTPMediaType.fileExtension(path.fileExt) ?? Self.defaultMediaType
        let context: Renderer.Context
        do { context = try req.tau.flattenContexts(self[contentType] ?? [:]) }
        catch {
            return req.eventLoop.future(error: moduleError)
        }
        
        return req.tau.renderer.render(template: relative,
                                        from: scope,
                                        context: context,
                                        options: [.caching(update ? .update : .default)])
            .map {
                var headers: HTTPHeaders = [:]
                let modTime = self[path]!.modTime.timeIntervalSinceReferenceDate
                headers.contentType = contentType
                headers.add(name: .eTag, value: modTime.description)
                return Response(status: .ok, headers: headers, body: .init(buffer: $0))
            }
    }
    
    func stream(_ path: String, on req: Request) -> EventLoopFuture<Response> {
        req.eventLoop.future(req.fileio.streamFile(at: path))
    }
    
    func contextualize(_ dir: String, on req: Request) {
        let files = (try? FileManager.default
            .contentsOfDirectory(at: URL(fileURLWithPath: dir, isDirectory: true),
                                 includingPropertiesForKeys: FileTemplateMiddleware.DirectoryIndexing.keys,
                                 options: FileTemplateMiddleware.DirectoryIndexing.options)) ?? []
        
        let object = TemplateData.dictionary(
            ["absolutePath": dir,
             "requestPath": dir.count == self.dir.count ? "/"
                          : String(dir[self.dir.index(before: self.dir.endIndex)..<dir.endIndex]),
             "files": files.map {$0._templateData}  ])
        
        try? req.tau.context.register(object: object,
                                       toScope: "index",
                                       type: [.default, .lockContextVariables])
    }
    
    func checkSource(_ req: Request) -> EventLoopFuture<Response>? {
        if req.tau.renderer.sources.all.contains(scope) { return nil }
        do {
            try req.tau.renderer.sources
                   .register(source: scope,
                             using: FileSource(fileio: req.application.fileio,
                                                 sandboxDirectory: dir,
                                                 viewDirectory: dir,
                                                 defaultExtension: TemplateSources.defaultExtension),
                             searchable: false)
            return nil
        }
        catch {
            return req.eventLoop.future(error: error)
        }
    }
}

private extension FileTemplateMiddleware.DirectoryIndexing {
    var valid: Bool {
        switch self {
            case .relative(let p): return !p.isEmpty && !p.contains("/")
            case .absolute(let p): return !p.isEmpty && p.last != "/"
            default: return true
        }
    }
}
