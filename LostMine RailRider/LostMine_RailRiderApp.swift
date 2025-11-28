

import SwiftUI
import WebKit
import UIKit
import Network
import AppsFlyerLib

@main
struct LostMine_RailRiderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            LoadingView()
                .statusBar(hidden: true)
                .background(.black)
        }
    }
}

// MARK: - AppDelegate for AppsFlyer
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // Configure AppsFlyer
        AppsFlyerLib.shared().appsFlyerDevKey = "HDkuzr5J8n3KXydd8BQaPi"
        AppsFlyerLib.shared().appleAppID = "6755871200"
        AppsFlyerLib.shared().isDebug = false // Set to true for development, false for production
        
        // Start AppsFlyer
        AppsFlyerLib.shared().start()
        
        print("🚀 AppsFlyer initialized with ID: \(AppsFlyerLib.shared().getAppsFlyerUID())")
        
        return true
    }
    
    // Handle deep links if needed
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        AppsFlyerLib.shared().handleOpen(url, options: options)
        return true
    }
    
    // Handle push notifications if needed
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        AppsFlyerLib.shared().handlePushNotification(userInfo)
    }
}

// MARK: - Network Monitor
class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    @Published var isConnected = false

    init() {
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.isConnected = path.status == .satisfied
                print("🌐 Network status: \(self.isConnected ? "Connected" : "Disconnected")")
            }
        }
        monitor.start(queue: queue)
    }
}

// MARK: - UserDefaults Manager
class AppStateManager: ObservableObject {
    private let hasAppBeenOpenedBeforeKey = "hasAppBeenOpenedBefore"
    private let savedWebViewURLKey = "savedWebViewURL"

    @Published var hasAppBeenOpenedBefore: Bool {
        didSet {
            UserDefaults.standard.set(hasAppBeenOpenedBefore, forKey: hasAppBeenOpenedBeforeKey)
        }
    }

    var savedWebViewURL: URL? {
        get {
            if let urlString = UserDefaults.standard.string(forKey: savedWebViewURLKey) {
                return URL(string: urlString)
            }
            return nil
        }
        set {
            if let url = newValue {
                UserDefaults.standard.set(url.absoluteString, forKey: savedWebViewURLKey)
            } else {
                UserDefaults.standard.removeObject(forKey: savedWebViewURLKey)
            }
        }
    }

    init() {
        // Check if app has been opened before
        self.hasAppBeenOpenedBefore = UserDefaults.standard.bool(forKey: hasAppBeenOpenedBeforeKey)

        if !hasAppBeenOpenedBefore {
            // Mark as opened for next time
            UserDefaults.standard.set(true, forKey: hasAppBeenOpenedBeforeKey)
            print("📱 First time app opening - will show native app")
        } else {
            print("📱 App has been opened before - saved URL: \(savedWebViewURL?.absoluteString ?? "None")")
        }
    }

    func saveWebViewURL(_ url: URL) {
        savedWebViewURL = url
        print("💾 Saved WebView URL: \(url.absoluteString)")
    }

    func clearSavedURL() {
        savedWebViewURL = nil
        print("🗑️ Cleared saved WebView URL")
    }
}

// MARK: - Server Response Handler
class ServerResponseHandler: ObservableObject {
    @Published var shouldShowWebView = false
    @Published var webViewURL: URL?
    @Published var isLoading = false // Only for webview loading
    @Published var webViewHasFailed = false

    private let appStateManager: AppStateManager
    
    private var serverURL: String {
        if let url = Bundle.main.object(forInfoDictionaryKey: "ServerBaseURL") as? String {
            return url + "/ios-lostmine-railrider/server.php"
        }
        return "https://gtappinfo.site/ios-lostmine-railrider/server.php"
    }

    init(appStateManager: AppStateManager) {
        self.appStateManager = appStateManager
    }

    private func getDeviceLanguage() -> String {
        if let preferredLanguage = Locale.preferredLanguages.first {
            let languageCode = extractLanguageCode(from: preferredLanguage)
            print("✅ Using language: \(languageCode)")
            return languageCode
        }

        if let currentLanguage = Locale.current.language.languageCode?.identifier {
            return currentLanguage
        }

        return "en"
    }

    private func extractLanguageCode(from localeString: String) -> String {
        let components = localeString.split(separator: "-")
        if let firstComponent = components.first {
            return String(firstComponent).lowercased()
        }
        return localeString.lowercased()
    }

    private func getDeviceRegion() -> String {
        if let region = Locale.current.region?.identifier {
            return region
        }
        return ""
    }

    func checkServerStatus(completion: @escaping (Bool) -> Void) {
        print("🔍 Starting server check in background...")

        let deviceModel = UIDevice.current.model
        let systemVersion = UIDevice.current.systemVersion
        let language = getDeviceLanguage()
        let country = getDeviceRegion()
        
        // Get AppsFlyer ID
        let appsFlyerID = AppsFlyerLib.shared().getAppsFlyerUID()
    

        // Build the URL with parameters including AppsFlyer ID
        let urlString = "\(serverURL)?p=Bs2675kDjkb5Ga&os=iOS%20\(systemVersion)&lng=\(language)&devicemodel=\(deviceModel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceModel)&country=\(country.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? country)&appsflyerid=\(appsFlyerID)"

        print("🔗 Full URL with AppsFlyer: \(urlString)")

        // URL encode the parameters properly
        guard let encodedURLString = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encodedURLString) else {
            print("❌ ERROR: Invalid server URL components")
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }

        print("🔗 Final Encoded URL: \(url.absoluteString)")
        print("📱 AppsFlyer ID: \(appsFlyerID)")

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            print("📨 Received server response")

            if let error = error {
                print("❌ NETWORK ERROR: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("📊 HTTP Status Code: \(httpResponse.statusCode)")

                // Check if status code indicates success
                guard (200...299).contains(httpResponse.statusCode) else {
                    print("❌ HTTP ERROR: Status code \(httpResponse.statusCode)")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }
            }

            guard let data = data else {
                print("❌ ERROR: No data received from server")
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            guard let responseString = String(data: data, encoding: .utf8) else {
                print("❌ ERROR: Cannot decode response data as string")
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            print("📝 Raw server response: \(responseString)")
            print("📝 Response length: \(responseString.count) characters")

            let success = self.processServerResponse(responseString)

            DispatchQueue.main.async {
                if success, let url = self.webViewURL {
                    // Save the URL for future use
                    self.appStateManager.saveWebViewURL(url)
                    print("✅ Server check successful, URL saved for future use")

                    // CRITICAL FIX: Immediately notify that we should show WebView
                    self.shouldShowWebView = true
                }
                completion(success)
            }
        }

        task.resume()
    }

    private func processServerResponse(_ response: String) -> Bool {
        print("🔍 Processing server response...")

        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedResponse.isEmpty else {
            print("❌ ERROR: Empty response from server")
            return false
        }

        print("📝 Raw response: '\(trimmedResponse)'")

        // Try direct URL first
        if let url = URL(string: trimmedResponse), isValidURL(trimmedResponse) {
            DispatchQueue.main.async {
                self.webViewURL = url
            }
            print("✅ SUCCESS: Direct URL accepted: \(url)")
            return true
        }

        // Try token#url format
        let components = trimmedResponse.split(separator: "#")

        if components.count >= 2 {
            let urlString = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)

            if let url = URL(string: urlString), isValidURL(urlString) {
                DispatchQueue.main.async {
                    self.webViewURL = url
                }
                print("✅ SUCCESS: URL extracted from token#url format: \(url)")
                return true
            }
        }

        // Try any component as URL
        for component in components {
            let possibleURL = String(component).trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: possibleURL), isValidURL(possibleURL) {
                DispatchQueue.main.async {
                    self.webViewURL = url
                }
                print("✅ SUCCESS: URL found in components: \(url)")
                return true
            }
        }

        print("❌ ERROR: No valid URL found in response")
        return false
    }

    private func isValidURL(_ string: String) -> Bool {
        // Basic URL validation
        guard let url = URL(string: string) else { return false }

        // Check if it has a valid scheme
        guard let scheme = url.scheme else { return false }

        // Valid schemes for web URLs
        let validSchemes = ["http", "https", "ftp"]
        if !validSchemes.contains(scheme) {
            return false
        }

        // Check if it has a host
        guard let host = url.host else { return false }

        // Basic host validation (should contain a dot for domain or be localhost)
        if !host.contains(".") && host != "localhost" {
            return false
        }

        print("✅ URL validation passed: \(string)")
        return true
    }
}

struct LoadingView: View {
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var appStateManager = AppStateManager()
    @StateObject private var serverHandler: ServerResponseHandler

    @State private var hasCheckedServer = false
    @State private var currentViewState: ViewState = .determining
    @State private var showGlobalLoadingOverlay = true

    enum ViewState {
        case determining
        case nativeApp
        case webView
    }

    init() {
        let appStateManager = AppStateManager()
        _serverHandler = StateObject(wrappedValue: ServerResponseHandler(appStateManager: appStateManager))
    }

    var body: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)

            // Global loading overlay that persists across transitions
            if showGlobalLoadingOverlay {
                LoadingOverlay()
                    .zIndex(1)
            }

            switch currentViewState {
            case .determining:
                Color.clear

            case .webView:
                if let url = getWebViewURL() {
                    WebViewContainer(
                        url: url,
                        serverHandler: serverHandler,
                        networkMonitor: networkMonitor,
                        onFail: handleWebViewFailure,
                        onWebViewReady: handleWebViewReady
                    )
                } else {
                    NativeAppContent()
                }

            case .nativeApp:
                NativeAppContent()
                    .onAppear {
                        hideGlobalLoadingOverlay()
                    }
            }
        }
        .onAppear {
            determineInitialView()
        }
        .onChange(of: networkMonitor.isConnected) { oldValue, newValue in
            handleNetworkChange(newValue: newValue)
        }
        .onChange(of: serverHandler.shouldShowWebView) { oldValue, newValue in
            if newValue && serverHandler.webViewURL != nil {
                print("🚀 IMMEDIATE SWITCH: Server provided URL, switching to WebView")
                switchToWebView()
            }
        }
    }

    // MARK: - Helper Views

    private func NativeAppContent() -> some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)

            SplashScreenView()
                .preferredColorScheme(.light)
        }
    }

    private struct WebViewContainer: View {
        let url: URL
        @ObservedObject var serverHandler: ServerResponseHandler
        @ObservedObject var networkMonitor: NetworkMonitor
        let onFail: () -> Void
        let onWebViewReady: () -> Void
        @State private var showOfflineMessage = false

        var body: some View {
            ZStack {
                SystemWebView(
                    url: url,
                    isLoading: $serverHandler.isLoading,
                    hasFailed: $serverHandler.webViewHasFailed
                )
                .edgesIgnoringSafeArea(.all)

                if showOfflineMessage && !networkMonitor.isConnected {
                    VStack {
                        HStack {
                            Image(systemName: "wifi.slash")
                                .foregroundColor(.white)
                                .font(.system(size: 14))
                            Text("No Internet Connection")
                                .font(.caption)
                                .foregroundColor(.white)
                            Spacer()
                            Button("OK") {
                                showOfflineMessage = false
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.top, 50)
                        Spacer()
                    }
                    .transition(.move(edge: .top))
                }
            }
            .onAppear {
                showOfflineMessage = !networkMonitor.isConnected
                print("🌐 WebView appeared - Internet: \(networkMonitor.isConnected), Show offline message: \(showOfflineMessage)")
            }
            .onChange(of: networkMonitor.isConnected) { oldValue, newValue in
                if newValue {
                    withAnimation {
                        showOfflineMessage = false
                    }
                } else {
                    withAnimation {
                        showOfflineMessage = true
                    }
                }
            }
            .onChange(of: serverHandler.isLoading) { oldValue, newValue in
                if !newValue {
                    print("🌐 WebView finished initial loading, notifying parent")
                    onWebViewReady()
                }
            }
            .onChange(of: serverHandler.webViewHasFailed) { oldValue, newValue in
                if newValue {
                    print("🌐 WebView failed")
                    onWebViewReady()
                }
            }
        }
    }

    private struct LoadingOverlay: View {
        var body: some View {
            ZStack {
                Color.black
                    .edgesIgnoringSafeArea(.all)

                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(2.0)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))

                    Text("Loading...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - Logic Methods

    private func getWebViewURL() -> URL? {
        return appStateManager.savedWebViewURL ?? serverHandler.webViewURL
    }

    private func determineInitialView() {
        print("📱 Determining initial view...")
        print("📱 Has been opened before: \(appStateManager.hasAppBeenOpenedBefore)")
        print("📱 Saved URL: \(appStateManager.savedWebViewURL?.absoluteString ?? "None")")
        print("🌐 Internet available: \(networkMonitor.isConnected)")

        currentViewState = .determining
        showGlobalLoadingOverlay = true

        // CLIENT REQUIREMENT 1: First time app launch always shows native part
        if !appStateManager.hasAppBeenOpenedBefore {
            print("📱 FIRST LAUNCH: Always show native app")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.switchToNativeApp()
                // Try to get URL from server for future use if network available
                if self.networkMonitor.isConnected {
                    self.checkServerInBackground()
                }
            }
            return
        }

        // For subsequent launches
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // CLIENT REQUIREMENT 2: If URL is saved, ALWAYS show webview
            if let savedURL = self.appStateManager.savedWebViewURL {
                print("📱 SAVED URL FOUND: Always show WebView")
                self.serverHandler.webViewURL = savedURL
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.switchToWebView()
                }
            } else {
                // CLIENT REQUIREMENT 3: If no saved URL
                if self.networkMonitor.isConnected {
                    print("🌐 No saved URL but internet available → contacting server")
                    self.checkServerInBackground()

                    // Wait for server response
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                        if self.appStateManager.savedWebViewURL == nil {
                            print("⏳ Server did not respond → showing Native App")
                            self.switchToNativeApp()
                        } else {
                            print("✅ Server responded with URL → showing WebView")
                            self.switchToWebView()
                        }
                    }
                } else {
                    // CLIENT REQUIREMENT: No saved URL + no internet → show native app
                    print("🚫 No saved URL and no internet → showing Native App")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.switchToNativeApp()
                    }
                }
            }
        }
    }

    private func handleNetworkChange(newValue: Bool) {
        if newValue && currentViewState == .nativeApp && !hasCheckedServer {
            checkServerInBackground()
        }
    }

    private func checkServerInBackground() {
        guard !hasCheckedServer else {
            print("🔍 Server already checked, skipping")
            return
        }

        hasCheckedServer = true
        print("🔍 Starting background server check...")

        serverHandler.checkServerStatus { success in
            DispatchQueue.main.async {
                if success {
                    print("✅ Server check successful - URL saved for next launch")
                    // If we're currently in native app and got a URL, switch to webview
                    if self.currentViewState == .nativeApp && self.serverHandler.webViewURL != nil {
                        print("🚀 BACKGROUND CHECK: URL received, switching to WebView immediately")
                        self.switchToWebView()
                    }
                } else {
                    print("❌ Server check failed")
                }

                // Reset for next potential check
                self.hasCheckedServer = false
            }
        }
    }

    private func handleWebViewFailure() {
        print("🌐 WebView failed, but staying in webview as per client requirement")
        hideGlobalLoadingOverlay()
    }

    private func handleWebViewReady() {
        print("🌐 WebView is ready, hiding global loading overlay")
        hideGlobalLoadingOverlay()
    }

    private func hideGlobalLoadingOverlay() {
        withAnimation(.easeOut(duration: 0.3)) {
            showGlobalLoadingOverlay = false
        }
    }

    private func switchToWebView() {
        print("🔄 Switching to webview")
        withAnimation(.easeInOut(duration: 0.3)) {
            currentViewState = .webView
        }
    }

    private func switchToNativeApp() {
        print("🔄 Switching to native app")
        withAnimation(.easeInOut(duration: 0.3)) {
            currentViewState = .nativeApp
        }
        hideGlobalLoadingOverlay()
    }
}

// MARK: - WebView Implementation
struct SystemWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var hasFailed: Bool

    class CoordinatorState {
        var hasLoaded = false
        var currentURL: URL?
        var isFirstLoad = true
    }

    func makeUIView(context: Context) -> WKWebView {
        print("🌐 Creating WKWebView for URL: \(url)")

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"

        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = true
        webView.allowsBackForwardNavigationGestures = true

        // Load the URL immediately when creating the view
        loadURL(in: webView, coordinator: context.coordinator)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload if URL has changed
        if context.coordinator.state.currentURL != url {
            print("🌐 URL changed, reloading WebView: \(url)")
            loadURL(in: webView, coordinator: context.coordinator)
        }
    }

    private func loadURL(in webView: WKWebView, coordinator: Coordinator) {
        print("🌐 Loading URL in WebView: \(url)")

        // Reset initial load state internally
        coordinator.state.isFirstLoad = true
        coordinator.state.currentURL = url

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-us", forHTTPHeaderField: "Accept-Language")

        webView.load(request)
        coordinator.state.hasLoaded = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: SystemWebView
        let state = CoordinatorState()

        init(_ parent: SystemWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.parent.hasFailed = false
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.state.isFirstLoad = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.hasFailed = true
                self.state.isFirstLoad = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.hasFailed = true
                self.state.isFirstLoad = false
            }
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            let redirectURL = webView.url?.absoluteString ?? "unknown"
            print("🔄 WebView server redirect to: \(redirectURL)")
        }

        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                if let serverTrust = challenge.protectionSpace.serverTrust {
                    let credential = URLCredential(trust: serverTrust)
                    completionHandler(.useCredential, credential)
                    return
                }
            }
            completionHandler(.performDefaultHandling, nil)
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            completionHandler()
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            let targetURL = navigationAction.request.url?.absoluteString ?? "unknown"
            print("🪟 WebView opening new window for: \(targetURL)")

            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}


