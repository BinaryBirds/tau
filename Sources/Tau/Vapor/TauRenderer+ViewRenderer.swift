import Vapor

extension TemplateEngine: ViewRenderer {
    public func `for`(_ request: Request) -> ViewRenderer { request.tau }

    public func render<E>(_ name: String,
                          _ context: E) -> EventLoopFuture<View> where E: Encodable {
        guard let context = Renderer.Context(encodable: context) else {
            return eventLoop.future(error: "Provided context failed to encode or is not a dictionary")
        }
        return render(template: name, context: context)
    }
}
