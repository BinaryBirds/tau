import Vapor

extension HTTPMediaType: TemplateDataRepresentable {
    public static var TemplateDataType: TemplateDataType? { .dictionary }
    public var TemplateData: TemplateData { .dictionary([
        "type": type,
        "subType": subType,
        "parameters": parameters,
        "serialized": serialize(),
    ]) }
}
