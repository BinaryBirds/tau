import Tau
import XCTVapor
import NIOConcurrencyHelpers

class TauTests: TauTestClass {

    func testApplication() throws {
        app.views.use(.tau)

        app.get("test-file") { $0.view.render("Views/test", ["foo": "bar"]) }

        try app.test(.GET, "test-file", afterResponse: {
            XCTAssertEqual($0.status, .ok)
            XCTAssertEqual($0.headers.contentType, .html)
            XCTAssertContains($0.body.string, "test: bar")
        })
    }
    
    func testSandboxing() throws {
        TemplateEngine.sources = .singleSource(FileSource(fileio: app.fileio,
                                                        limits: .default,
                                                        sandboxDirectory: projectFolder,
                                                        viewDirectory: templateFolder))
        
        app.views.use(.tau)

        app.get("hello") { $0.view.render("hello") }
        app.get("allowed") { $0.view.render("../hello") }
        app.get("sandboxed") { $0.view.render("../../hello") }

        try app.test(.GET, "hello", afterResponse: {
            XCTAssertEqual($0.status, .ok)
            XCTAssertEqual($0.headers.contentType, .html)
            XCTAssertEqual($0.body.string, "Hello, world!\n")
        })
        
        try app.test(.GET, "allowed", afterResponse: {
            XCTAssertEqual($0.status, .internalServerError)
            XCTAssert($0.body.string.contains("No template found"))
        })
        
        try app.test(.GET, "sandboxed", afterResponse: {
            XCTAssertEqual($0.status, .internalServerError)
            XCTAssert($0.body.string.contains("Attempted to escape sandbox"))
        })
    }

    func testContextRequest() throws {
        struct RequestPath: UnsafeEntity, EmptyParams, StringReturn {
            var unsafeObjects: UnsafeObjects? = nil
            
            func evaluate(_ params: CallValues) -> TemplateData {
                .string(self.req?.url.path)
            }
        }
        
        let test = MemorySource()
        
        TemplateEngine.rootDirectory = "/"
        TemplateEngine.sources = .singleSource(test)
        TemplateEngine.entities.use(RequestPath(), asFunction: "path")
                
        test["/foo.html"] = """
        Hello #(name ?? "Unknown user") @ #(path() ?? "Could not retrieve path")
        """
        
        app.views.use(.tau)

        app.get("test-file") {
            $0.tau.render(template: "foo",
                           context: ["name": "vapor"],
                           options: [.caching(.bypass)])
        }

        try app.test(.GET, "test-file", afterResponse: {
            XCTAssertEqual($0.status, .ok)
            XCTAssertEqual($0.headers.contentType, .html)
            XCTAssertEqual($0.body.string, "Hello vapor @ /test-file")
        })
    }
    
    func testContextUserInfo() throws {
        struct CustomTag: UnsafeEntity, EmptyParams, StringReturn {
            var unsafeObjects: UnsafeObjects? = nil
        
            func evaluate(_ params: CallValues) -> TemplateData {
                .string(unsafeObjects?["info"] as? String) }
        }
        
        let test = MemorySource()
        test["/foo.html"] = "Hello #custom()!"
        
        TemplateEngine.rootDirectory = "/"
        TemplateEngine.sources = .singleSource(test)
        
        TemplateEngine.entities.use(CustomTag(), asFunction: "custom")
        
        app.views.use(.tau)
        try app.tau.context.register(object: "World", toScope: "info", type: .unsafe)
        
        app.get("test-file") {
            $0.tau.render(template: "foo", context: ["name": "vapor"])
        }

        try app.test(.GET, "test-file", afterResponse: {
            XCTAssertEqual($0.status, .ok)
            XCTAssertEqual($0.headers.contentType, .html)
            XCTAssertEqual($0.body.string, "Hello World!")
        })
    }
    
    func testLiteralContext() throws {
        let test = MemorySource()
        test["/template.html"] = """
        Debug: #($app.isRelease != true)
        URI: #($req.url)
        """
        
        var isReleaseRequired: Bool {
            try! TemplateEngine.cache.info(for: .searchKey("template"),
                                                 on: app.tau.eventLoop)
                .wait()!.requiredVars.contains("$app.isRelease")
        }
        
        TemplateEngine.sources = .singleSource(test)
                
        app.views.use(.tau)
        app.middleware.use(ExtensionMiddleware())
        
        try app.tau.context.register(generators: app.customVars, toScope: "app")
        
        app.get("template") { $0.tau.render(template: "template", options: [.caching(.update)]) }
        
        try app.test(.GET, "template")
        XCTAssertTrue(isReleaseRequired)
        
        try app.tau.context.lockAsLiteral(in: "app", key: "isRelease")
        try app.test(.GET, "template", afterResponse: {
            XCTAssertEqual($0.status, .ok)
            XCTAssertEqual($0.headers.contentType, .html)
            XCTAssertEqual($0.body.string, """
            Debug: true
            URI: ["host": , "isSecure": , "path": "/template", "port": , "query": ]
            """)
        })
        XCTAssertTrue(!isReleaseRequired)
    }
}

extension Application {
    var customVars: [String: TemplateDataGenerator] {
        ["isRelease": .immediate(environment.isRelease)]
    }
}

extension Request {
    var customVars: [String: TemplateDataGenerator] {
        ["url": .lazy(["isSecure": TemplateData.bool(self.url.scheme?.contains("https")),
                        "host": TemplateData.string(self.url.host),
                        "port": TemplateData.int(self.url.port),
                        "path": TemplateData.string(self.url.path),
                        "query": TemplateData.string(self.url.query)]),
        ]
    }
}

struct ExtensionMiddleware: Middleware {
    func respond(to request: Request,
                 chainingTo next: Responder) -> EventLoopFuture<Response> {
        do {
            try request.tau.context.register(generators: request.customVars, toScope: "req")
            return next.respond(to: request)
        }
        catch { return request.eventLoop.makeFailedFuture(error) }
    }
}
