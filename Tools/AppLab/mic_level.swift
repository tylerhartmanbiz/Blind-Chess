// Host loopback check: records the default INPUT device for N seconds and prints the
// peak RMS level (dBFS). Run while play_phrase.sh is playing to prove that output ->
// loopback -> input works on this Mac:  swift Tools/AppLab/mic_level.swift 6
import AVFoundation
import Foundation

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "6") ?? 6
let engine = AVAudioEngine()
let input = engine.inputNode
let format = input.outputFormat(forBus: 0)
print("[mic_level] input format: \(format)")
var peak: Float = 0
var buffers = 0
let lock = NSLock()
input.installTap(onBus: 0, bufferSize: 4096, format: format) { buf, _ in
    guard let ch = buf.floatChannelData else { return }
    let n = Int(buf.frameLength)
    var sum: Float = 0
    for i in 0..<n { sum += ch[0][i] * ch[0][i] }
    let rms = n > 0 ? (sum / Float(n)).squareRoot() : 0
    lock.lock(); peak = max(peak, rms); buffers += 1; lock.unlock()
}
do { try engine.start() } catch { print("[mic_level] engine start failed: \(error)"); exit(2) }
Thread.sleep(forTimeInterval: seconds)
engine.stop()
let db = peak > 0 ? 20 * log10(peak) : -999
print(String(format: "[mic_level] buffers=%d peakRMS=%.5f (%.1f dBFS) -> %@", buffers, peak, db,
             peak > 0.001 ? "SIGNAL" : "SILENCE"))
