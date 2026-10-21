//
//  WebView.swift
//  Blind Chess
//
//  chess.com's "play the computer" page with the bridge script injected at document start (page content world).
//

import SwiftUI
import WebKit

struct ChessWebView: UIViewRepresentable {
    static let url = URL(string: "https://www.chess.com/play/computer")!

    let bridge: ChessComBridge

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let scripts = config.userContentController
        scripts.addUserScript(WKUserScript(source: ChessComBridge.script, injectionTime: .atDocumentStart,
                                           forMainFrameOnly: true))
        scripts.add(WeakScriptHandler(bridge), name: ChessComBridge.handlerName)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        bridge.webView = webView
        webView.load(URLRequest(url: Self.url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(bridge: bridge) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let bridge: ChessComBridge

        init(bridge: ChessComBridge) {
            self.bridge = bridge
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Log.info("chess.com loaded: \(webView.url?.absoluteString ?? "-")")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Log.error("navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Log.error("page load failed: \(error.localizedDescription)")
            bridge.onEvent?(.loadFailed(error.localizedDescription))
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Log.error("web content process terminated, reloading")
            webView.reload()
        }
    }
}
