//
//  ChessJSBridge.swift
//  Blind Chess
//
//  Created by Tyler Hartman on 8/13/26.
//

import Foundation

struct ChessJSBridge {
    static func injectionScript() -> String {
        let css = """
        (function() {
            var style = document.createElement('style');
            style.innerHTML = `
                /* Hide the top navigation and ads to save space */
                #cc-header, .nav-container, .board-layout-ad { display: none !important; }

                /* Force the main container to take full width */
                .board-layout-main {
                    width: 100% !important;
                    margin: 0 !important;
                    padding: 0 !important;
                    display: block !important;
                }

                /* Make the board itself fill the width */
                chess-board, .board {
                    width: 98vw !important;
                    height: 98vw !important;
                    margin: 0 auto !important;
                }

                /* Ensure the page is still scrollable */
                body, html {
                    overflow-y: auto !important;
                    height: auto !important;
                }
            `;
            document.head.appendChild(style);

            // Scroll to the board automatically after it loads
            setTimeout(() => {
                const board = document.querySelector('chess-board') || document.querySelector('.board');
                if (board) board.scrollIntoView({block: "center"});
            }, 500);
        })();
        """

        return css
    }

    static func scrapeScript() -> String {
        let js = """
        (function() {
            let board = Array(8).fill(null).map(() => Array(8).fill(""));
            const pieces = document.querySelectorAll('.piece');

            const firstCoordinate = document.querySelector('text.coordinate-light, text.coordinate-dark');
                    let isWhiteSide = true;
                    if (firstCoordinate && firstCoordinate.textContent === '1') {
                        isWhiteSide = false;
                    }

            pieces.forEach(p => {
                const classes = p.className.split(' ');
                let type = "";
                let squareClass = "";

                classes.forEach(c => {
                    if (c.length === 2 && (c[0] === 'w' || c[0] === 'b')) type = c;
                    if (c.startsWith('square-')) squareClass = c;
                });

                if (type && squareClass) {
                    const coords = squareClass.replace('square-', '');
                    const file = parseInt(coords[0]) - 1;
                    const rank = 8 - parseInt(coords[1]);

                    let pieceChar = type[1];
                    if (type[0] === 'w') pieceChar = pieceChar.toUpperCase();

                    if (rank >= 0 && rank < 8 && file >= 0 && file < 8) {
                        board[rank][file] = pieceChar;
                    }
                }
            });
            
            // Try to detect en passant target square from highlighted moves
            let enPassantTarget = null;
            const highlightedSquares = document.querySelectorAll('.highlight');
            
            // Check if the last move was a two-square pawn advance
            if (highlightedSquares.length === 2) {
                const squares = Array.from(highlightedSquares).map(sq => {
                    const classes = sq.className.split(' ');
                    for (let cls of classes) {
                        if (cls.startsWith('square-')) {
                            return cls.replace('square-', '');
                        }
                    }
                    return null;
                }).filter(s => s);
                
                if (squares.length === 2) {
                    const from = squares[0];
                    const to = squares[1];
                    const fromFile = from[0];
                    const fromRank = parseInt(from[1]);
                    const toFile = to[0];
                    const toRank = parseInt(to[1]);
                    
                    // Check if this was a two-square pawn move
                    if (fromFile === toFile && Math.abs(toRank - fromRank) === 2) {
                        // Check if there's a pawn at the destination
                        const destRow = 8 - toRank;
                        const destCol = parseInt(fromFile) - 1;
                        const piece = board[destRow][destCol];
                        
                        if (piece === 'p' || piece === 'P') {
                            // En passant target is the square between from and to
                            const targetRank = (fromRank + toRank) / 2;
                            const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
                            enPassantTarget = files[parseInt(fromFile) - 1] + targetRank;
                        }
                    }
                }
            }
            
            return { board: board, isWhiteSide: isWhiteSide, enPassantTarget: enPassantTarget };
        })();
        """
        return js
    }

    static func moveScript(from: String, to: String, isWhite: Bool) -> String {
        let js = """
        (function() {
            const board = document.querySelector('chess-board') || document.querySelector('.board');
            if (!board) return 'JS ERR: Board not found';

            const boardRect = board.getBoundingClientRect();
            const squareSize = boardRect.width / 8;
            const isWhite = \(isWhite); // 👈 Dynamically injected

            function getCoords(squareStr) {
                const sq = parseInt(squareStr);
                const file = Math.floor(sq / 10);
                const rank = sq % 10;

                let visualFile, visualRank;

                if (isWhite) {
                    // White perspective: File 1 is left, Rank 8 is top
                    visualFile = file - 1;
                    visualRank = 8 - rank;
                } else {
                    // Black perspective: File 8 is left, Rank 1 is top
                    visualFile = 8 - file;
                    visualRank = rank - 1;
                }

                const x = boardRect.left + (visualFile * squareSize) + (squareSize / 2);
                const y = boardRect.top + (visualRank * squareSize) + (squareSize / 2);
                return { x, y };
            }

            const start = getCoords("\(from)");
            const end = getCoords("\(to)");

            const piece = document.querySelector('.piece.square-\(from)');
            if (!piece) return 'JS ERR: Piece .square-\(from) not found';

            const downEv = { bubbles: true, clientX: start.x, clientY: start.y, pointerType: 'touch' };
            piece.dispatchEvent(new PointerEvent('pointerdown', downEv));
            piece.dispatchEvent(new PointerEvent('pointerup', downEv));

            setTimeout(() => {
                const moveEv = { bubbles: true, clientX: end.x, clientY: end.y, pointerType: 'touch' };
                const target = document.elementFromPoint(end.x, end.y) || board;
                target.dispatchEvent(new PointerEvent('pointerdown', moveEv));
                target.dispatchEvent(new PointerEvent('pointerup', moveEv));
                
                // Use MouseEvent click which works on all elements
                const clickEvent = new MouseEvent('click', {
                    bubbles: true,
                    cancelable: true,
                    view: window,
                    clientX: end.x,
                    clientY: end.y
                });
                target.dispatchEvent(clickEvent);
            }, 250);

            return 'JS OK: Moving \(from) to \(to) (Flipped: ' + !isWhite + ')';
        })();
        """
        return js
    }
    
    static func touchScript(at square: String, isWhite: Bool) -> String {
        let js = """
        (function() {
            const board = document.querySelector('chess-board') || document.querySelector('.board');
            if (!board) return 'JS ERR: Board not found';

            const boardRect = board.getBoundingClientRect();
            const squareSize = boardRect.width / 8;
            const isWhitePerspective = \(isWhite);

            const sq = parseInt("\(square)");
            const file = Math.floor(sq / 10);
            const rank = sq % 10;

            let visualFile, visualRank;
            if (isWhitePerspective) {
                visualFile = file - 1;
                visualRank = 8 - rank;
            } else {
                visualFile = 8 - file;
                visualRank = rank - 1;
            }

            const x = boardRect.left + (visualFile * squareSize) + (squareSize / 2);
            const y = boardRect.top + (visualRank * squareSize) + (squareSize / 2);

            // Dispatch events directly to whatever is at those coordinates
            const target = document.elementFromPoint(x, y);
            if (target) {
                const evOpts = { bubbles: true, clientX: x, clientY: y, pointerType: 'touch', view: window };
                target.dispatchEvent(new PointerEvent('pointerdown', evOpts));
                target.dispatchEvent(new PointerEvent('pointerup', evOpts));
                
                // Use MouseEvent click which works on all elements
                const clickEvent = new MouseEvent('click', {
                    bubbles: true,
                    cancelable: true,
                    view: window,
                    clientX: x,
                    clientY: y
                });
                target.dispatchEvent(clickEvent);
                
                return 'JS OK: Touched \(square) at (' + x + ', ' + y + ')';
            }
            return 'JS ERR: No target at coords';
        })();
        """
        return js
    }
    
    /// Print the board state with row, column, and piece information
    static func printBoardScript() -> String {
        let js = """
        (function() {
            let board = Array(8).fill(null).map(() => Array(8).fill(""));
            const pieces = document.querySelectorAll('.piece');
            
            // Determine perspective
            const firstCoordinate = document.querySelector('text.coordinate-light, text.coordinate-dark');
            let isWhiteSide = true;
            if (firstCoordinate && firstCoordinate.textContent === '1') {
                isWhiteSide = false;
            }
            
            // Map pieces to board
            pieces.forEach(p => {
                const classes = p.className.split(' ');
                let type = "";
                let squareClass = "";
                
                classes.forEach(c => {
                    if (c.length === 2 && (c[0] === 'w' || c[0] === 'b')) type = c;
                    if (c.startsWith('square-')) squareClass = c;
                });
                
                if (type && squareClass) {
                    const coords = squareClass.replace('square-', '');
                    const file = parseInt(coords[0]);
                    const rank = parseInt(coords[1]);
                    
                    let pieceChar = type[1];
                    if (type[0] === 'w') pieceChar = pieceChar.toUpperCase();
                    
                    const boardRow = 8 - rank;
                    const boardCol = file - 1;
                    
                    if (boardRow >= 0 && boardRow < 8 && boardCol >= 0 && boardCol < 8) {
                        board[boardRow][boardCol] = pieceChar;
                    }
                }
            });
            
            // Create formatted output
            let output = '\\n=== CHESS BOARD STATE ===\\n';
            output += 'Perspective: ' + (isWhiteSide ? 'White' : 'Black') + '\\n\\n';
            output += '    A  B  C  D  E  F  G  H\\n';
            output += '  ┌──┬──┬──┬──┬──┬──┬──┬──┐\\n';
            
            const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
            const pieceNames = {
                'P': 'WP', 'N': 'WN', 'B': 'WB', 'R': 'WR', 'Q': 'WQ', 'K': 'WK',
                'p': 'BP', 'n': 'BN', 'b': 'BB', 'r': 'BR', 'q': 'BQ', 'k': 'BK'
            };
            
            for (let row = 0; row < 8; row++) {
                const rank = 8 - row;
                output += rank + ' │';
                
                for (let col = 0; col < 8; col++) {
                    const piece = board[row][col];
                    const display = piece ? pieceNames[piece] : '  ';
                    output += display + '│';
                }
                
                output += ' ' + rank + '\\n';
                
                if (row < 7) {
                    output += '  ├──┼──┼──┼──┼──┼──┼──┼──┤\\n';
                }
            }
            
            output += '  └──┴──┴──┴──┴──┴──┴──┴──┘\\n';
            output += '    A  B  C  D  E  F  G  H\\n\\n';
            
            // Add detailed list of pieces
            output += '=== PIECE POSITIONS ===\\n';
            for (let row = 0; row < 8; row++) {
                const rank = 8 - row;
                for (let col = 0; col < 8; col++) {
                    const file = files[col];
                    const piece = board[row][col];
                    if (piece) {
                        const color = piece === piece.toUpperCase() ? 'White' : 'Black';
                        const pieceName = {
                            'p': 'Pawn', 'n': 'Knight', 'b': 'Bishop',
                            'r': 'Rook', 'q': 'Queen', 'k': 'King'
                        }[piece.toLowerCase()];
                        output += 'Row ' + row + ', Col ' + col + ' (' + file + rank + '): ' + color + ' ' + pieceName + '\\n';
                    }
                }
            }
            
            return output;
        })();
        """
        return js
    }
    
    /// Find a piece of the given type that can move to the target square
    static func findPieceScript(pieceType: String?, targetSquare: String, isWhite: Bool, enPassantTarget: String? = nil) -> String {
        let pieceChar: String
        if let type = pieceType?.lowercased() {
            switch type {
            case "king": pieceChar = isWhite ? "K" : "k"
            case "queen": pieceChar = isWhite ? "Q" : "q"
            case "rook": pieceChar = isWhite ? "R" : "r"
            case "bishop": pieceChar = isWhite ? "B" : "b"
            case "knight": pieceChar = isWhite ? "N" : "n"
            case "pawn": pieceChar = isWhite ? "P" : "p"
            default: pieceChar = ""
            }
        } else {
            pieceChar = ""
        }
        
        let enPassantJS: String
        if let target = enPassantTarget {
            // Convert "e6" to file/rank numbers
            let file = Int(target.lowercased().unicodeScalars.first!.value) - 96 // a=1
            let rank = Int(String(target.suffix(1)))!
            enPassantJS = "const enPassantFile = \(file); const enPassantRank = \(rank);"
        } else {
            enPassantJS = "const enPassantFile = null; const enPassantRank = null;"
        }
        
        let js = """
        (function() {
            const targetFile = Math.floor(\(targetSquare) / 10);
            const targetRank = \(targetSquare) % 10;
            const targetSquareStr = 'square-' + targetFile + targetRank;
            \(enPassantJS)
            
            // Special handling for king (castling detection)
            if ("\(pieceChar.lowercased())" === "k") {
                // For castling, king should be on e-file (file 5)
                const kingStartFile = 5;
                const kingStartRank = \(isWhite) ? 1 : 8;
                
                // Check if this is a castling move (king moving to c or g file)
                if ((targetFile === 3 || targetFile === 7) && targetRank === kingStartRank) {
                    // Return king starting position + target position for castling
                    return kingStartFile.toString() + kingStartRank.toString() + targetFile.toString() + targetRank.toString();
                }
            }
            
            // Get all pieces of the specified type (or all pieces if no type specified)
            let pieces;
            if ("\(pieceChar)") {
                pieces = document.querySelectorAll('.piece.\(isWhite ? "w" : "b")\(pieceChar.lowercased())');
            } else {
                pieces = document.querySelectorAll('.piece.\(isWhite ? "w" : "b")p, .piece.\(isWhite ? "w" : "b")n, .piece.\(isWhite ? "w" : "b")b, .piece.\(isWhite ? "w" : "b")r, .piece.\(isWhite ? "w" : "b")q, .piece.\(isWhite ? "w" : "b")k');
            }
            
            // Try to find a piece that can reach the target square
            // For pawns, prioritize same-file forward moves, then en passant, then diagonal captures
            let bestMove = null;
            let enPassantMove = null;
            
            for (let piece of pieces) {
                const classes = piece.className.split(' ');
                let fromSquare = null;
                
                for (let cls of classes) {
                    if (cls.startsWith('square-')) {
                        fromSquare = cls.replace('square-', '');
                        break;
                    }
                }
                
                if (fromSquare) {
                    const fromFile = parseInt(fromSquare[0]);
                    const fromRank = parseInt(fromSquare[1]);
                    
                    const fileDiff = Math.abs(fromFile - targetFile);
                    const rankDiff = Math.abs(fromRank - targetRank);
                    const signedRankDiff = \(isWhite) ? (targetRank - fromRank) : (fromRank - targetRank);
                    
                    // Check if this piece can geometrically reach the target
                    let canReach = false;
                    
                    if ("\(pieceChar.lowercased())" === "p") {
                        // Pawn logic
                        // Check for en passant first (highest priority for diagonal moves to empty square)
                        if (enPassantFile !== null && enPassantRank !== null && 
                            targetFile === enPassantFile && targetRank === enPassantRank &&
                            fileDiff === 1 && signedRankDiff === 1) {
                            // This is an en passant capture!
                            enPassantMove = fromSquare + targetFile + targetRank;
                            continue; // Keep looking for other possibilities
                        }
                        
                        // For forward moves (fileDiff === 0), pawn MUST be on same file
                        if (fileDiff === 0 && fromFile === targetFile && (signedRankDiff === 1 || (signedRankDiff === 2 && (\(isWhite) ? fromRank === 2 : fromRank === 7)))) {
                            // Perfect match - forward move on same file, return immediately
                            return fromSquare + targetFile + targetRank;
                        } else if (fileDiff === 1 && signedRankDiff === 1) {
                            // Regular diagonal capture - save as backup
                            if (!bestMove && !enPassantMove) {
                                bestMove = fromSquare + targetFile + targetRank;
                            }
                        }
                    } else if ("\(pieceChar.lowercased())" === "n") {
                        // Knight moves in L-shape: 2+1 or 1+2
                        canReach = (rankDiff === 2 && fileDiff === 1) || (rankDiff === 1 && fileDiff === 2);
                    } else if ("\(pieceChar.lowercased())" === "b") {
                        // Bishop moves diagonally
                        canReach = rankDiff === fileDiff && rankDiff > 0;
                    } else if ("\(pieceChar.lowercased())" === "r") {
                        // Rook moves straight
                        canReach = (fromFile === targetFile || fromRank === targetRank) && (fromFile !== targetFile || fromRank !== targetRank);
                    } else if ("\(pieceChar.lowercased())" === "q") {
                        // Queen moves like rook or bishop
                        const isDiag = rankDiff === fileDiff && rankDiff > 0;
                        const isStraight = (fromFile === targetFile || fromRank === targetRank) && (fromFile !== targetFile || fromRank !== targetRank);
                        canReach = isDiag || isStraight;
                    } else if ("\(pieceChar.lowercased())" === "k") {
                        // King moves one square
                        canReach = rankDiff <= 1 && fileDiff <= 1 && (rankDiff + fileDiff) > 0;
                    } else {
                        // Unknown piece type - allow it
                        canReach = true;
                    }
                    
                    // If this non-pawn piece can reach the target, return it
                    if (canReach && "\(pieceChar.lowercased())" !== "p") {
                        return fromSquare + targetFile + targetRank;
                    }
                }
            }
            
            // Return en passant move if found
            if (enPassantMove) {
                return enPassantMove;
            }
            
            // Return regular diagonal capture if found
            if (bestMove) {
                return bestMove;
            }
            
            return 'JS ERR: No valid piece found';
        })();
        """
        return js
    }
}
