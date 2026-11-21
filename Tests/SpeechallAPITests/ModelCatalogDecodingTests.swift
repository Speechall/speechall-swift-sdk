import Foundation
import SpeechallAPITypes
import Testing

@Test func modelCatalogDecodesUnknownValues() throws {
    let payload = Data("""
        [
            {
                "id": "futurecorp.model-x",
                "display_name": "Model X",
                "provider": "futurecorp",
                "is_available": true,
                "supports_srt": false,
                "supports_vtt": false,
                "model_type": "podcast",
                "accuracy_tier": "ultra"
            }
        ]
        """.utf8)

    let models = try JSONDecoder().decode([Components.Schemas.SpeechToTextModel].self, from: payload)
    let model = try #require(models.first)
    #expect(model.id == "futurecorp.model-x")
    #expect(model.provider == "futurecorp")
    #expect(model.model_type == "podcast")
    #expect(model.accuracy_tier == "ultra")
}
