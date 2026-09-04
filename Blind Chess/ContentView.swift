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
    @State private var pendingMove: ParsedMove? = nil
    @State private var pendingBoardState: ChessMoveValidator.BoardState? = nil
    @State private var awaitingDisambiguation: ChessMoveValidator.DisambiguationType = .none
    
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
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .onAppear {
            speechRecognizer.requestAuthorization()
        }
        .onChange(of: speechRecognizer.recognizedText) { oldValue, newValue in
            // Only process if text has changed and is not empty
            guard !newValue.isEmpty, newValue != lastProcessedText else { return }
            
            // Check if we're awaiting disambiguation
            if awaitingDisambiguation != .none, let pending = pendingMove, let boardState = pendingBoardState {
                lastProcessedText = newValue
                handleDisambiguation(response: newValue, originalMove: pending, boardState: boardState)
                return
            }
            
            // Try to parse the move
            if let parsedMove = ChessMoveParser.parse(transcript: newValue) {
                lastProcessedText = newValue
                executeMove(parsedMove)
            }
        }
    }
    
    private func handleDisambiguation(response: String, originalMove: ParsedMove, boardState: ChessMoveValidator.BoardState) {
        let lowercased = response.lowercased()
        
        // Extract file and/or rank from response
        var fromFile: String? = nil
        var fromRank: String? = nil
        
        // Look for file (a-h)
        for char in ["a", "b", "c", "d", "e", "f", "g", "h"] {
            if lowercased.contains(char) {
                fromFile = char
                break
            }
        }
        
        // Look for rank (1-8)
        for num in 1...8 {
            if lowercased.contains(String(num)) {
                fromRank = String(num)
                break
            }
        }
        
        // Get all valid moves again
        let toSquare = originalMove.coordinate
        let validMoves = ChessMoveValidator.findValidMovesTo(to: toSquare, pieceType: originalMove.piece, boardState: boardState)
        
        // Filter based on disambiguation
        var filteredMoves = validMoves
        if let file = fromFile {
            filteredMoves = filteredMoves.filter { $0.fileChar == file }
        }
        if let rank = fromRank {
            filteredMoves = filteredMoves.filter { $0.rank == rank }
        }
        
        // Reset disambiguation state
        awaitingDisambiguation = .none
        pendingMove = nil
        pendingBoardState = nil
        
        if filteredMoves.isEmpty {
            print("❌ No piece at specified position can reach target")
            moveStatus = "❌ No piece there"
            return
        }
        
        if filteredMoves.count > 1 {
            print("❌ Still ambiguous - need more info")
            moveStatus = "❌ Still ambiguous"
            return
        }
        
        // Found exactly one piece - execute the move!
        guard let webView = webView else {
            moveStatus = "❌ Board not loaded"
            return
        }
        
        let selectedMove = filteredMoves[0]
        print("🎯 Disambiguated to: \(selectedMove.piece) from \(selectedMove.fileChar.uppercased())\(selectedMove.rank)")
        
        // Execute the move directly
        moveStatus = "✅ Executing..."
        let fromSquare = selectedMove.from
        let toSquareActual = toSquare
        
        // Get perspective for JavaScript
        let scrapeJS = ChessJSBridge.scrapeScript()
        webView.evaluateJavaScript(scrapeJS) { result, error in
            guard let resultDict = result as? [String: Any],
                  let isWhiteSide = resultDict["isWhiteSide"] as? Bool else {
                moveStatus = "❌ Could not read board"
                return
            }
            
            let moveJS = ChessJSBridge.moveScript(from: fromSquare, to: toSquareActual, isWhite: isWhiteSide)
            webView.evaluateJavaScript(moveJS) { moveResult, moveError in
                if let result = moveResult as? String, result.contains("OK") {
                    moveStatus = "✅ Moved to \(originalMove.file.uppercased())\(originalMove.rank)"
                    
                    // Print board
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let printJS = ChessJSBridge.printBoardScript()
                        webView.evaluateJavaScript(printJS) { printResult, _ in
                            if let boardState = printResult as? String {
                                print(boardState)
                            }
                        }
                    }
                } else {
                    moveStatus = "❌ Move failed"
                }
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
            
            // Get en passant target if available
            let enPassantTarget = resultDict["enPassantTarget"] as? String
            
            // Parse board state and print piece counts
            guard let boardState = ChessMoveValidator.BoardState.from(scriptResult: resultDict) else {
                print("❌ Could not parse board state")
                moveStatus = "❌ Board state error"
                return
            }
            
            let pieceCounts = boardState.countPieces()
            var countStr = "📊 Your pieces: "
            let pieceNames = ["P": "Pawns", "N": "Knights", "B": "Bishops", "R": "Rooks", "Q": "Queens", "K": "King"]
            for (piece, count) in pieceCounts.sorted(by: { $0.key < $1.key }) {
                if count > 0 {
                    countStr += "\(count) \(pieceNames[piece] ?? piece) "
                }
            }
            print(countStr)
            
            print("📍 Moving \(move.piece ?? "piece") to \(move.file.uppercased())\(move.rank) (square: \(toSquare))")
            moveStatus = "✅ Checking moves..."
            
            // DEBUG: Print king position
            if let kingPos = boardState.findKing(forWhite: isWhiteSide) {
                let kingFile = String(UnicodeScalar(UInt8(kingPos.col) + 97))  // 0=a, 1=b, etc.
                let kingRank = 8 - kingPos.row
                print("👑 Your King is at: \(kingFile.uppercased())\(kingRank)")
            }
            
            // Check if multiple pieces can reach the target BEFORE selecting one
            let validMoves = ChessMoveValidator.findValidMovesTo(to: toSquare, pieceType: move.piece, boardState: boardState)
            
            if validMoves.count > 1 {
                // Multiple pieces can reach - need disambiguation
                let ambiguityType = ChessMoveValidator.analyzeAmbiguity(validMoves: validMoves)
                
                print("ℹ️ \(validMoves.count) \(move.piece ?? "piece")(s) can reach this square:")
                for validMove in validMoves {
                    print("   - \(validMove.piece) from \(validMove.fileChar.uppercased())\(validMove.rank)")
                }
                
                // Ask for disambiguation
                switch ambiguityType {
                case .needFile:
                    let files = validMoves.map { $0.fileChar.uppercased() }.joined(separator: ", ")
                    moveStatus = "Which file? (\(files))"
                    pendingMove = move
                    pendingBoardState = boardState
                    awaitingDisambiguation = .needFile
                case .needRank:
                    let ranks = validMoves.map { $0.rank }.joined(separator: ", ")
                    moveStatus = "Which rank? (\(ranks))"
                    pendingMove = move
                    pendingBoardState = boardState
                    awaitingDisambiguation = .needRank
                case .needBoth:
                    moveStatus = "Which piece? (say file and rank)"
                    pendingMove = move
                    pendingBoardState = boardState
                    awaitingDisambiguation = .needBoth
                case .none:
                    moveStatus = "❌ Ambiguous move"
                }
                return
            }
            
            if validMoves.isEmpty {
                print("❌ No valid \(move.piece ?? "piece") can reach \(move.file.uppercased())\(move.rank)")
                
                // Additional debug: Try to understand WHY the move is invalid
                if move.piece?.lowercased() == "king", let kingPos = boardState.findKing(forWhite: isWhiteSide) {
                    let kingFile = kingPos.col + 1
                    let kingRank = 8 - kingPos.row
                    let fromSquare = "\(kingFile)\(kingRank)"
                    
                    print("   🔍 Attempting to validate King move from \(fromSquare) to \(toSquare)")
                    let testValidation = ChessMoveValidator.validateMove(from: fromSquare, to: toSquare, boardState: boardState)
                    if !testValidation.isValid {
                        print("   ⚠️  Reason: \(testValidation.errorMessage ?? "Unknown")")
                    }
                }
                
                moveStatus = "❌ No \(move.piece ?? "piece") can reach there"
                return
            }
            
            // Only one valid move - use it directly
            print("🎯 Selected: \(validMoves[0].piece) from \(validMoves[0].fileChar.uppercased())\(validMoves[0].rank)")
            moveStatus = "✅ Executing move..."
            
            // Use the validated move directly
            let fromSquare = validMoves[0].from
            let toSquareActual = toSquare
            
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

// MARK: - Button Mode View
struct ButtonModeView: View {
    @State private var selectedPiece: ChessPieceType? = nil
    @State private var selectedFile: String? = nil
    @State private var selectedRank: Int? = nil
    @State private var moveStatus: String = ""
    @State private var ambiguousMoves: [(from: String, piece: String, fileChar: String, rank: String)] = []
    @State private var pendingToSquare: String = ""
    @State private var pendingIsWhiteSide: Bool = true
    @State private var pendingTargetLabel: String = ""
    @Binding var webView: WKWebView?

    var body: some View {
        VStack(spacing: 15) {
            // Move status feedback at top
            if !moveStatus.isEmpty {
                Text(moveStatus)
                    .font(.subheadline)
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .multilineTextAlignment(.center)
            }

            if !ambiguousMoves.isEmpty {
                Spacer()

                // One button per candidate piece that can reach the target square
                VStack(spacing: 12) {
                    ForEach(ambiguousMoves, id: \.from) { candidate in
                        DisambiguationButton(candidate: candidate) {
                            resolveDisambiguation(candidate: candidate)
                        }
                    }
                }

                Spacer()
            } else {
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
                .padding(.top, moveStatus.isEmpty ? 20 : 5)

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
                    executeButtonMove()
                }) {
                    Text("Move")
                        .font(.system(size: 20))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(canMakeMove ? Color(red: 0.506, green: 0.714, blue: 0.298) : Color.gray)  // Chess.com green or gray if disabled
                        .cornerRadius(12)
                }
                .disabled(!canMakeMove)
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .padding(.horizontal, 8)
    }

    private var canMakeMove: Bool {
        selectedFile != nil && selectedRank != nil
    }

    private var statusColor: Color {
        if moveStatus.contains("✅") { return .green }
        if moveStatus.contains("❌") { return .red }
        return .white
    }

    private func executeButtonMove() {
        guard let file = selectedFile?.lowercased(),
              let rank = selectedRank else {
            moveStatus = "❌ Select a square first"
            return
        }

        // Create ParsedMove from button selections
        let move = ParsedMove(
            piece: selectedPiece?.rawValue,
            file: file,
            rank: String(rank)
        )

        print("🎮 Button move: \(move.piece ?? "Any piece") to \(file.uppercased())\(rank)")

        guard let webView = webView else {
            moveStatus = "❌ Board not loaded"
            return
        }

        // Execute the move using the same logic as voice mode
        executeMove(move, webView: webView)
    }

    private func executeMove(_ move: ParsedMove, webView: WKWebView) {
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

            guard let boardState = ChessMoveValidator.BoardState.from(scriptResult: resultDict) else {
                print("❌ Could not parse board state")
                moveStatus = "❌ Board state error"
                return
            }

            let pieceCounts = boardState.countPieces()
            var countStr = "📊 Your pieces: "
            let pieceNames = ["P": "Pawns", "N": "Knights", "B": "Bishops", "R": "Rooks", "Q": "Queens", "K": "King"]
            for (piece, count) in pieceCounts.sorted(by: { $0.key < $1.key }) {
                if count > 0 {
                    countStr += "\(count) \(pieceNames[piece] ?? piece) "
                }
            }
            print(countStr)

            print("📍 Moving \(move.piece ?? "piece") to \(move.file.uppercased())\(move.rank) (square: \(toSquare))")

            // Check if multiple pieces can reach the target BEFORE selecting one
            let validMoves = ChessMoveValidator.findValidMovesTo(to: toSquare, pieceType: move.piece, boardState: boardState)

            if validMoves.isEmpty {
                print("❌ No valid \(move.piece ?? "piece") can reach \(move.file.uppercased())\(move.rank)")
                moveStatus = "❌ No \(move.piece ?? "piece") can reach there"
                return
            }

            let targetLabel = "\(move.file.uppercased())\(move.rank)"

            if validMoves.count > 1 {
                print("ℹ️ \(validMoves.count) piece(s) can reach this square:")
                for validMove in validMoves {
                    print("   - \(validMove.piece) from \(validMove.fileChar.uppercased())\(validMove.rank)")
                }

                moveStatus = disambiguationMessage(validMoves: validMoves, targetLabel: move.file.lowercased() + move.rank)
                ambiguousMoves = validMoves
                pendingToSquare = toSquare
                pendingIsWhiteSide = isWhiteSide
                pendingTargetLabel = targetLabel
                return
            }

            // Only one valid move - use it directly
            print("🎯 Selected: \(validMoves[0].piece) from \(validMoves[0].fileChar.uppercased())\(validMoves[0].rank)")
            performMove(from: validMoves[0].from, to: toSquare, isWhiteSide: isWhiteSide, targetLabel: targetLabel, webView: webView)
        }
    }

    private func resolveDisambiguation(candidate: (from: String, piece: String, fileChar: String, rank: String)) {
        guard let webView = webView, !pendingToSquare.isEmpty else { return }

        let toSquare = pendingToSquare
        let isWhiteSide = pendingIsWhiteSide
        let targetLabel = pendingTargetLabel

        ambiguousMoves = []
        pendingToSquare = ""

        performMove(from: candidate.from, to: toSquare, isWhiteSide: isWhiteSide, targetLabel: targetLabel, webView: webView)
    }

    private func performMove(from: String, to: String, isWhiteSide: Bool, targetLabel: String, webView: WKWebView) {
        moveStatus = "✅ Moving..."

        let moveJS = ChessJSBridge.moveScript(from: from, to: to, isWhite: isWhiteSide)
        webView.evaluateJavaScript(moveJS) { moveResult, moveError in
            if let moveError = moveError {
                print("❌ Move error: \(moveError)")
                moveStatus = "❌ Move failed"
            } else if let result = moveResult as? String {
                print("✅ Move result: \(result)")
                if result.contains("OK") {
                    moveStatus = "✅ Moved to \(targetLabel)"

                    // Clear selections after successful move
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        selectedPiece = nil
                        selectedFile = nil
                        selectedRank = nil
                        moveStatus = ""
                    }

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

    /// Builds a message like "Two pawns can go to e4. Which pawn do you want to move?"
    private func disambiguationMessage(validMoves: [(from: String, piece: String, fileChar: String, rank: String)], targetLabel: String) -> String {
        let pieceNames = Set(validMoves.map { $0.piece })
        let pluralLabel: String
        let singularLabel: String
        if pieceNames.count == 1, let name = pieceNames.first {
            singularLabel = name.lowercased()
            pluralLabel = singularLabel + "s"
        } else {
            singularLabel = "piece"
            pluralLabel = "pieces"
        }

        return "\(numberWord(validMoves.count)) \(pluralLabel) can go to \(targetLabel). Which \(singularLabel) do you want to move?"
    }

    private func numberWord(_ n: Int) -> String {
        let words = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"]
        if n >= 0 && n < words.count {
            return words[n]
        }
        return "\(n)"
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

struct DisambiguationButton: View {
    let candidate: (from: String, piece: String, fileChar: String, rank: String)
    let action: () -> Void

    private var squareLabel: String {
        "\(candidate.fileChar.uppercased())\(candidate.rank)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(ChessPieceType(rawValue: candidate.piece)?.symbol ?? "")
                    .font(.system(size: 28))
                Text("\(candidate.piece) on \(squareLabel)")
                    .font(.system(size: 18))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 55)
            .background(Color.white)
            .foregroundColor(.black)
            .cornerRadius(10)
        }
        .accessibilityLabel("\(candidate.piece) on \(squareLabel)")
        .accessibilityHint("Double tap to move this \(candidate.piece.lowercased())")
        .padding(.horizontal, 20)
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

