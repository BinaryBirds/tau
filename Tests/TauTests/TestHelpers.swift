import Tau
import XCTTauKit
import XCTVapor
import NIOConcurrencyHelpers


class TauTestClass: TauKitTestCase {
    var app: Application { _app! }
    var _app: Application? = nil
    
    override func setUp() {
        _app = Application(.testing)
        TemplateEngine.cache.dropAll()
        TemplateEngine.rootDirectory = projectFolder
        TemplateEngine.sources = .init()
    }
    
    override func tearDown() { app.shutdown() }
}


var projectFolder: String { "/\(#file.split(separator: "/").dropLast(3).joined(separator: "/"))/" }
var templateFolder: String { projectFolder + "Views/" }
