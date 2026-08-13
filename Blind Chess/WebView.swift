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
        let webView = WKWebView(frame: .zero, configuration: config)
        
        DispatchQueue.main.async {
            self.webView = webView
        }
        
        webView.load(URLRequest(url: url))
        
        // Inject CSS after page loads
        webView.navigationDelegate = context.coordinator
        
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
                    print("CSS injection error: \(error)")
                } else {
                    print("CSS injected successfully")
                }
            }
        }
    }
}
