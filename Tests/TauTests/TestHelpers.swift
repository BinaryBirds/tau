import Tau
import XCTTauKit
import XCTVapor
import NIOConcurrencyHelpers


class TauTestClass: TauKitTestCase {

    var app: Application { _app! }
    var _app: Application? = nil
    
    var projectFolder: String { "/\(#file.split(separator: "/").dropLast().joined(separator: "/"))/" }
    var templateFolder: String { projectFolder + "Templates/" }

    override func setUp() {
        _app = Application(.testing)
        TemplateEngine.cache.dropAll()
        TemplateEngine.rootDirectory = templateFolder
        TemplateEngine.sources = .init()
    }
    
    override func tearDown() {
        app.shutdown()
    }
}


