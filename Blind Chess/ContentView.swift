//
//  ContentView.swift
//  Blind Chess
//
//  Created by Tyler Hartman on 8/13/26.
//

import SwiftUI
import WebKit

struct ContentView: View {
    // MARK: - State Variables
    @State private var isListening = false
    @State private var isButtonMode = false
    @State private var isTTSEnabled = true
    @State private var isBoardVisible = true
    @State private var webView: WKWebView? = nil
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top Window - 60% (Chess Board)
                if isBoardVisible {
                    ChessBoardWindow(webView: $webView)
                        .frame(height: geometry.size.height * 0.6)
                }
                
                // Bottom Window - 40% (Controls)
                ControlWindow(
                    isListening: $isListening,
                    isButtonMode: $isButtonMode,
                    isTTSEnabled: $isTTSEnabled,
                    isBoardVisible: $isBoardVisible,
                    webView: $webView
                )
                .frame(height: isBoardVisible ? geometry.size.height * 0.4 : geometry.size.height)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

// MARK: - Chess Board Window
struct ChessBoardWindow: View {
    @Binding var webView: WKWebView?
    
    var body: some View {
        if let url = URL(string: "https://www.chess.com/play/computer") {
            WebView(url: url, webView: $webView)
                .ignoresSafeArea(edges: .all)
        } else {
            // Fallback if URL is invalid
            Color.black
                .overlay(
                    Text("Unable to load chess board")
                        .foregroundColor(.white)
                )
        }
    }
}

// MARK: - Control Window
struct ControlWindow: View {
    @Binding var isListening: Bool
    @Binding var isButtonMode: Bool
    @Binding var isTTSEnabled: Bool
    @Binding var isBoardVisible: Bool
    @Binding var webView: WKWebView?
    
    var body: some View {
        ZStack {
            Color(white: 0.15)
            
            VStack(spacing: 0) {
                // Top Icon Bar
                HStack(spacing: 80) {
                    InputModeToggle(isButtonMode: $isButtonMode)
                        .frame(width: 30, height: 30)
                    TTSToggle(isTTSEnabled: $isTTSEnabled)
                        .frame(width: 30, height: 30)
                    BoardVisibilityToggle(isBoardVisible: $isBoardVisible)
                        .frame(width: 30, height: 30)
                }
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                // Main Content Area
                if isButtonMode {
                    ButtonModeView(webView: $webView)
                } else {
                    VoiceModeView(isListening: $isListening, webView: $webView)
                }
            }
        }
    }
}

// MARK: - Voice Mode View
struct VoiceModeView: View {
    @Binding var isListening: Bool
    @Binding var webView: WKWebView?
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var lastProcessedText: String = ""
    @State private var moveStatus: String = ""
    
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            
            // Large Microphone Button
            Button(action: {
                if isListening {
                    speechRecognizer.stopRecording()
                    isListening = false
                } else {
                    speechRecognizer.startRecording()
                    isListening = true
                }
            }) {
                ZStack {
                    Circle()
                        .fill(isListening ? Color.red : Color.blue)
                        .frame(width: 120, height: 120)
                        .shadow(radius: 10)
                    
                    Image(systemName: "mic.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                }
            }
            .accessibilityLabel(isListening ? "Listening" : "Tap to speak")
            .accessibilityHint("Double tap to toggle voice input")
            
            // Display recognized text
            Text(speechRecognizer.recognizedText.isEmpty ? (isListening ? "Listening..." : "Tap to speak") : speechRecognizer.recognizedText)
                .font(.headline)
                .padding(.top, 8)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Move status feedback
            if !moveStatus.isEmpty {
                Text(moveStatus)
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .padding(.horizontal, 20)
            }
            
            Spacer()
        }
        .onAppear {
            speechRecognizer.requestAuthorization()
        }
        .onChange(of: speechRecognizer.recognizedText) { oldValue, newValue in
            // Only process if text has changed and is not empty
            guard !newValue.isEmpty, newValue != lastProcessedText else { return }
            
            // Try to parse the move
            if let parsedMove = ChessMoveParser.parse(transcript: newValue) {
                lastProcessedText = newValue
                executeMove(parsedMove)
            }
        }
    }
    
    private func executeMove(_ move: ParsedMove) {
        guard let webView = webView else {
            moveStatus = "❌ Board not loaded"
            return
        }
        
        // First, scrape the board to determine perspective
        let scrapeJS = ChessJSBridge.scrapeScript()
        webView.evaluateJavaScript(scrapeJS) { result, error in
            if let error = error {
                print("❌ Scrape error: \(error)")
                moveStatus = "❌ Could not read board"
                return
            }
            
            guard let resultDict = result as? [String: Any],
                  let isWhiteSide = resultDict["isWhiteSide"] as? Bool else {
                print("❌ Could not determine board perspective")
                moveStatus = "❌ Could not determine board orientation"
                return
            }
            
            let toSquare = move.coordinate // e.g., "54" for e4
            
            print("📍 Moving \(move.piece ?? "piece") to \(move.file.uppercased())\(move.rank) (square: \(toSquare))")
            moveStatus = "✅ Finding piece..."
            
            // Find which piece can move to the target square
            let findPieceJS = ChessJSBridge.findPieceScript(pieceType: move.piece, targetSquare: toSquare, isWhite: isWhiteSide)
            webView.evaluateJavaScript(findPieceJS) { findResult, findError in
                if let findError = findError {
                    print("❌ Find piece error: \(findError)")
                    moveStatus = "❌ Could not find piece"
                    return
                }
                
                guard let moveStr = findResult as? String, !moveStr.contains("ERR") else {
                    print("❌ No valid piece found for move")
                    moveStatus = "❌ No valid \(move.piece ?? "piece") found"
                    return
                }
                
                // moveStr format: "fromSquare+toSquare" e.g., "5254" (e2 to e4)
                guard moveStr.count == 4 else {
                    print("❌ Invalid move string: \(moveStr)")
                    moveStatus = "❌ Invalid move"
                    return
                }
                
                let fromSquare = String(moveStr.prefix(2))
                let toSquareActual = String(moveStr.suffix(2))
                
                print("🎯 Checking if move is legal: \(fromSquare) → \(toSquareActual)")
                moveStatus = "✅ Validating move..."
                
                // Parse board state for validation
                guard let boardState = ChessMoveValidator.BoardState.from(scriptResult: resultDict) else {
                    print("❌ Could not parse board state")
                    moveStatus = "❌ Board state error"
                    return
                }
                
                // Validate the move
                let validation = ChessMoveValidator.validateMove(from: fromSquare, to: toSquareActual, boardState: boardState)
                
                if !validation.isValid {
                    print("❌ Illegal move: \(validation.errorMessage ?? "Unknown error")")
                    moveStatus = "❌ Illegal: \(validation.errorMessage ?? "Invalid move")"
                    return
                }
                
                print("✅ Move is legal, executing...")
                moveStatus = "✅ Moving..."
                
                // Execute the move
                let moveJS = ChessJSBridge.moveScript(from: fromSquare, to: toSquareActual, isWhite: isWhiteSide)
                webView.evaluateJavaScript(moveJS) { moveResult, moveError in
                    if let moveError = moveError {
                        print("❌ Move error: \(moveError)")
                        moveStatus = "❌ Move failed"
                    } else if let result = moveResult as? String {
                        print("✅ Move result: \(result)")
                        if result.contains("OK") {
                            moveStatus = "✅ Moved to \(move.file.uppercased())\(move.rank)"
                            
                            // Print the board after the move
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                let printJS = ChessJSBridge.printBoardScript()
                                webView.evaluateJavaScript(printJS) { printResult, printError in
                                    if let boardState = printResult as? String {
                                        print(boardState)
                                    } else if let error = printError {
                                        print("❌ Print board error: \(error)")
                                    }
                                }
                            }
                        } else {
                            moveStatus = "❌ Move failed"
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Button Mode View
struct ButtonModeView: View {
    @State private var selectedPiece: ChessPieceType? = nil
    @State private var selectedFile: String? = nil
    @State private var selectedRank: Int? = nil
    @Binding var webView: WKWebView?
    
    var body: some View {
        VStack(spacing: 15) {
            // Piece Selection
            HStack(spacing: 6) {
                ForEach(ChessPieceType.allCases, id: \.self) { piece in
                    PieceSelectionButton(
                        piece: piece,
                        isSelected: selectedPiece == piece
                    ) {
                        selectedPiece = piece
                    }
                }
            }
            .padding(.top, 20)
            
            // File Selection (A-H)
            HStack(spacing: 7) {
                ForEach(["A", "B", "C", "D", "E", "F", "G", "H"], id: \.self) { file in
                    FileRankButton(
                        label: file,
                        isSelected: selectedFile == file
                    ) {
                        selectedFile = file
                    }
                }
            }
            
            // Rank Selection (1-8)
            HStack(spacing: 7) {
                ForEach(1...8, id: \.self) { rank in
                    FileRankButton(
                        label: "\(rank)",
                        isSelected: selectedRank == rank
                    ) {
                        selectedRank = rank
                    }
                }
            }
            
            Spacer()
            
            // Make Move Button
            Button(action: {
                // Handle make move action
                print("Make move: \(selectedPiece?.name ?? "none") to \(selectedFile ?? "?")\(selectedRank ?? 0)")
            }) {
                Text("Make Move")
                    .font(.system(size: 20))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(red: 0.15, green: 0.8, blue: 0.15))  // Medium green
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Toggle Components
struct InputModeToggle: View {
    @Binding var isButtonMode: Bool
    
    var body: some View {
        Button(action: {
            isButtonMode.toggle()
        }) {
            Image(systemName: isButtonMode ? "mic.fill" : "hand.point.up.left.fill")
                .font(.system(size: 24))
                .foregroundColor(.white)
        }
        .accessibilityLabel(isButtonMode ? "Button mode active" : "Voice mode active")
        .accessibilityHint("Double tap to switch input mode")
    }
}

struct TTSToggle: View {
    @Binding var isTTSEnabled: Bool
    
    var body: some View {
        Button(action: {
            isTTSEnabled.toggle()
        }) {
            Image(systemName: isTTSEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill")
                .font(.system(size: 24))
                .foregroundColor(isTTSEnabled ? .white : .gray)
        }
        .accessibilityLabel(isTTSEnabled ? "Text to speech enabled" : "Text to speech disabled")
        .accessibilityHint("Double tap to toggle text to speech")
    }
}

struct BoardVisibilityToggle: View {
    @Binding var isBoardVisible: Bool
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                isBoardVisible.toggle()
            }
        }) {
            Image(systemName: isBoardVisible ? "eye.fill" : "eye.slash.fill")
                .font(.system(size: 24))
                .foregroundColor(isBoardVisible ? .white : .gray)
        }
        .accessibilityLabel(isBoardVisible ? "Board visible" : "Board hidden")
        .accessibilityHint("Double tap to toggle board visibility")
    }
}

// MARK: - Button Components
struct PieceSelectionButton: View {
    let piece: ChessPieceType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {  // Changed from 2 to 0 to move text closer
                Text(piece.symbol)
                    .font(.system(size: 33.6))
                    .padding(.bottom, -3)  // Move text up by reducing bottom padding
                Text(piece.name)
                    .font(.system(size: 11.88))  // 10.8 * 1.1 = 11.88
                    .fontWeight(.medium)
            }
            .frame(width: 55, height: 55)
            .background(isSelected ? Color.blue : Color.white)
            .foregroundColor(isSelected ? .white : .black)
            .cornerRadius(10)
        }
        .accessibilityLabel("\(piece.name) piece")
        .accessibilityHint("Double tap to select \(piece.name)")
    }
}

struct FileRankButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18))
                .fontWeight(.bold)
                .frame(width: 38, height: 38)
                .background(isSelected ? Color.blue : Color.white)
                .foregroundColor(isSelected ? .white : .black)
                .cornerRadius(8)
        }
        .accessibilityLabel(label)
        .accessibilityHint("Double tap to select \(label)")
    }
}

// MARK: - Chess Piece Type Enum
enum ChessPieceType: String, CaseIterable {
    case king = "King"
    case queen = "Queen"
    case rook = "Rook"
    case bishop = "Bishop"
    case knight = "Knight"
    case pawn = "Pawn"
    
    var name: String {
        self.rawValue
    }
    
    var symbol: String {
        switch self {
        case .king: return "♔"
        case .queen: return "♕"
        case .rook: return "♖"
        case .bishop: return "♗"
        case .knight: return "♘"
        case .pawn: return "♙"
        }
    }
}

