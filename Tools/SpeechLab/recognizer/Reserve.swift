import Foundation
import Speech
/// SpeechTranscriber assets need the locale reserved for this client first.
func reserveLocaleHook() async -> String {
    guard #available(macOS 26, iOS 26, *) else { return "n/a" }
    do {
        let ok = try await AssetInventory.reserve(locale: Locale(identifier: "en-US"))
        return "reserved=\(ok) reservedLocales=\(await AssetInventory.reservedLocales.map { $0.identifier })"
    } catch { return "reserve-error: \(describe(error))" }
}
