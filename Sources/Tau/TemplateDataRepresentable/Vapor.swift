import Vapor

extension HTTPMediaType: TemplateDataRepresentable {
    
    public var templateData: TemplateData {
        .dictionary([
            "type": type,
            "subType": subType,
            "parameters": parameters,
            "serialized": serialize(),
        ])
    }
}
