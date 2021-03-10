import Vapor

public extension Application {
    var tau: TemplateEngine { .init(self) }
}

public extension UnsafeEntity {
    var app: Application? { unsafeObjects?["app"] as? Application }
}

extension Application: ContextPublisher {
    public var templateVariables: [String : TemplateDataGenerator] { [:] }
}
