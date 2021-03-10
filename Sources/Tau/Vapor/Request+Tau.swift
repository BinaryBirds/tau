import Vapor

public extension Request {
    var tau: TemplateEngine { .init(self.application, self) }
}

public extension UnsafeEntity {
    var req: Request? { unsafeObjects?["req"] as? Request }
}

extension Request: ContextPublisher {
    public var templateVariables: [String : TemplateDataGenerator] { [:] }
}
