//
//  SpeechRecognizer.swift
//  Blind Chess
//
//  Created by Tyler Hartman on 8/13/26.
//

import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
class SpeechRecognizer: ObservableObject {
    @Published var recognizedText: String = ""
    @Published var isRecording: Bool = false
    
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // Silence detection
    private var silenceTimer: Task<Void, Never>?
    
    // Request authorization
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("✅ Speech recognition authorized")
                case .denied:
                    print("❌ Speech recognition denied")
                case .restricted:
                    print("❌ Speech recognition restricted")
                case .notDetermined:
                    print("⚠️ Speech recognition not determined")
                @unknown default:
                    print("❌ Unknown authorization status")
                }
            }
        }
    }
    
    // Start recording
    func startRecording() {
        // Stop any existing recording
        stopRecording()
        
        print("🎤 Starting recording...")
        
        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Create recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                print("❌ Unable to create recognition request")
                return
            }
            
            recognitionRequest.shouldReportPartialResults = true
            
            // Get audio input
            let inputNode = audioEngine.inputNode
            
            // Start recognition task
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                
                if let result = result {
                    let transcript = result.bestTranscription.formattedString
                    
                    Task { @MainActor in
                        self.recognizedText = transcript
                        print("📝 Recognized: \(transcript)")
                        
                        // Reset silence timer whenever new words are detected
                        self.resetSilenceTimer()
                    }
                }
                
                if let error = error {
                    print("❌ Recognition error: \(error.localizedDescription)")
                }
            }
            
            // Configure audio input
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }
            
            // Start audio engine
            audioEngine.prepare()
            try audioEngine.start()
            
            isRecording = true
            recognizedText = ""
            print("✅ Recording started successfully")
            
        } catch {
            print("❌ Error starting recording: \(error.localizedDescription)")
            isRecording = false
        }
    }
    
    // Stop recording
    func stopRecording() {
        print("🛑 Stopping recording...")
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Cancel silence timer
        silenceTimer?.cancel()
        silenceTimer = nil
        
        isRecording = false
        print("✅ Recording stopped")
    }
    
    // MARK: - Silence Detection
    
    /// Resets the silence timer. If no new words are detected within 5 seconds,
    /// the transcript will be cleared to prevent old partial transcriptions from interfering.
    private func resetSilenceTimer() {
        // Cancel existing timer
        silenceTimer?.cancel()
        
        // Start new timer
        silenceTimer = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                
                // Clear transcript after 5 seconds of silence
                print("🔇 5 seconds of silence detected - clearing transcript and restarting recognition")
                self.recognizedText = ""
                
                // Restart the recognition task to clear the buffer
                if self.isRecording {
                    self.restartRecognition()
                }
            } catch {
                // Task was cancelled (new words came in)
            }
        }
    }
    
    /// Restarts the recognition task without stopping the audio engine
    private func restartRecognition() {
        // Cancel current recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionRequest?.endAudio()
        
        // Create new recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("❌ Unable to create recognition request during restart")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Start new recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcript = result.bestTranscription.formattedString
                
                Task { @MainActor in
                    self.recognizedText = transcript
                    print("📝 Recognized: \(transcript)")
                    
                    // Reset silence timer whenever new words are detected
                    self.resetSilenceTimer()
                }
            }
            
            if let error = error {
                print("❌ Recognition error: \(error.localizedDescription)")
            }
        }
        
        print("✅ Recognition task restarted")
    }
}
