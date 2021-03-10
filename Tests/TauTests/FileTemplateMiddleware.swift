import Tau
import XCTVapor
import NIOConcurrencyHelpers

class FileTemplateMiddlewareTests: TauTestClass {
    
    private var dir: String {
        "/" + #file.split(separator: "/").dropLast().joined(separator: "/") + "/Templates/"
    }

    func setupMiddleware() throws {
        print(dir)
        
        let middleware = FileTemplateMiddleware(publicDirectory: dir)
        
        if let lfm = middleware { app.middleware.use(lfm) }
        else { throw "Couldn't initialize middleware" }
        
        FileTemplateMiddleware.defaultContext?.options = [.missingVariableThrows(false)]
        
        app.views.use(.tau)
    }
    
    func testBasic() throws {
        try setupMiddleware()
        
        try app.testable().test(.GET, "/Tau.html") {
            XCTAssertEqual($0.body.string, "Tau\nNo Version Set\n") }
        
        try app.testable().test(.GET, "/TauAs.html") {
            XCTAssertEqual($0.body.string, "Tau\n") }
        
        try app.testable().test(.GET, "/NoTauAs.html") {
            XCTAssertEqual($0.body.string, "No Tau Here\n") }
        
        XCTAssertTrue(TemplateEngine.cache.count == 2)
    }
    
    func testProhibit() throws {
        FileTemplateMiddleware.directoryIndexing = .prohibit
        try setupMiddleware()
        
        try app.testable().test(.GET, "/") {
            XCTAssert($0.body.string.contains("Directory indexing disallowed")) }
    }
    
    func testIgnore() throws {
        FileTemplateMiddleware.directoryIndexing = .ignore
        try setupMiddleware()
                
        try app.testable().test(.GET, "/") {
            XCTAssert($0.body.string.contains("Not Found")) }
    }
    
    func testRelative() throws {
        FileTemplateMiddleware.directoryIndexing = .relative("Index.html")
        try setupMiddleware()
                
        try app.testable().test(.GET, "/") {
            XCTAssert($0.body.string.contains("Contents of /")) }
    }
    
    func testAbsolute() throws {
        FileTemplateMiddleware.directoryIndexing = .absolute(dir + "Index.html")
        try setupMiddleware()
                
        try app.testable().test(.GET, "/") {
            print($0.body.string)
            XCTAssert($0.body.string.contains("Contents of /")) }
        
        try app.testable().test(.GET, "/More/") {
            print($0.body.string)
            XCTAssert($0.body.string.contains("Contents of /More")) }
    }
    
    func testTypeContext() throws {
        try setupMiddleware()
        
        FileTemplateMiddleware.defaultContext?["version"] = "1.0.0"
        
        try app.testable().test(.GET, "/Tau.html") {
            XCTAssert($0.body.string.contains("1.0.0"))
            FileTemplateMiddleware.defaultContext?["version"] = nil
        }
    }
}



