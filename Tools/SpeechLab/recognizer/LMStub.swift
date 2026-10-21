import Foundation
import Speech
func buildLanguageModel() async throws -> AnyObject {
    throw NSError(domain: "speechlab", code: 2, userInfo: [NSLocalizedDescriptionKey: "custom LM code did not compile on this SDK"])
}
func applyLM(_ lm: AnyObject, to req: SFSpeechRecognitionRequest) {}
