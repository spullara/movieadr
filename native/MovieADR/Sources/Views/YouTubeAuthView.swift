import SwiftUI
import WebKit

struct YouTubeAuthView: View {
    @Binding var isPresented: Bool
    var onCookiesObtained: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to YouTube")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    // Extract cookies and dismiss
                    extractCookies()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            YouTubeWebView(onCookiesObtained: { cookies in
                onCookiesObtained(cookies)
                isPresented = false
            })
        }
        .frame(width: 800, height: 600)
    }

    private func extractCookies() {
        // Trigger cookie extraction from the WebView
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let youtubeCookies = cookies.filter {
                $0.domain.contains("youtube.com") || $0.domain.contains("google.com")
            }
            let netscapeString = Self.toNetscapeFormat(youtubeCookies)
            onCookiesObtained(netscapeString)
            isPresented = false
        }
    }

    static func toNetscapeFormat(_ cookies: [HTTPCookie]) -> String {
        var lines = ["# Netscape HTTP Cookie File"]
        for cookie in cookies {
            let domain = cookie.domain
            let flag = domain.hasPrefix(".") ? "TRUE" : "FALSE"
            let path = cookie.path
            let secure = cookie.isSecure ? "TRUE" : "FALSE"
            let expiry = cookie.expiresDate.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
            let name = cookie.name
            let value = cookie.value
            lines.append("\(domain)\t\(flag)\t\(path)\t\(secure)\t\(expiry)\t\(name)\t\(value)")
        }
        return lines.joined(separator: "\n")
    }
}

struct YouTubeWebView: NSViewRepresentable {
    var onCookiesObtained: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/")!
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookiesObtained: onCookiesObtained)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var onCookiesObtained: (String) -> Void

        init(onCookiesObtained: @escaping (String) -> Void) {
            self.onCookiesObtained = onCookiesObtained
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Check if we've landed on YouTube (meaning login succeeded)
            if let url = webView.url, url.host?.contains("youtube.com") == true {
                // Give a moment for cookies to settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                        let ytCookies = cookies.filter {
                            $0.domain.contains("youtube.com") || $0.domain.contains("google.com")
                        }
                        if ytCookies.contains(where: { $0.name == "SID" || $0.name == "SSID" }) {
                            let netscape = YouTubeAuthView.toNetscapeFormat(ytCookies)
                            self.onCookiesObtained(netscape)
                        }
                    }
                }
            }
        }
    }
}
