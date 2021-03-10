import Foundation
import Vapor

extension URL {

    var _TemplateData: TemplateData {
        var values = (try? resourceValues(forKeys: .init(FileTemplateMiddleware.DirectoryIndexing.keys)))?._TemplateData ?? [:]
        values["name"] = lastPathComponent
        values["absolutePath"] = absoluteString
        values["pathComponents"] = pathComponents
        values["mimeType"] = HTTPMediaType.fileExtension(pathExtension) ?? .plainText
        return .dictionary(values)
    }
}

extension URLResourceValues {

    var _TemplateData: [String: TemplateDataRepresentable] {
        [
            "isApplication": isApplication,
            "isDirectory": isDirectory,
            "isRegularFile": isRegularFile,
            "isHidden": isHidden,
            "isSymbolicLink": isSymbolicLink,
            "fileSize": fileSize,
            "creationDate": creationDate, // returns nil on Ubuntu xenial
            "contentModificationDate": contentModificationDate,
        ]
        
    }
}
