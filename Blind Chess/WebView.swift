//
//  WebView.swift
//  Blind Chess
//
//  Created by Tyler Hartman on 8/13/26.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var webView: WKWebView?
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // Configure WebView preferences for better performance
        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        
        // Allow inline media playback
        config.allowsInlineMediaPlayback = true
        
        // Suppress rendering until content is loaded
        config.suppressesIncrementalRendering = false
        
        let webView = WKWebView(frame: .zero, configuration: config)
        
        // Set navigation delegate first
        webView.navigationDelegate = context.coordinator
        
        // Allow back/forward gestures
        webView.allowsBackForwardNavigationGestures = false
        
        // Set to opaque for better performance
        webView.isOpaque = true
        webView.backgroundColor = .black
        
        DispatchQueue.main.async {
            self.webView = webView
        }
        
        // Create and load request
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 30
        
        webView.load(request)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No need to update
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Inject CSS to make board bigger
            webView.evaluateJavaScript(ChessJSBridge.injectionScript()) { result, error in
                if let error = error {
                    print("❌ CSS injection error: \(error.localizedDescription)")
                } else {
                    print("✅ CSS injected successfully")
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ Navigation failed: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("❌ Provisional navigation failed: \(error.localizedDescription)")
        }
        
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            print("⚠️ WebContent process terminated, reloading...")
            webView.reload()
        }
    }
}
