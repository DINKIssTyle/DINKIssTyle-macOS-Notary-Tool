import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct NotaryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Create NotaryService as a shared environment object
    @StateObject private var notaryService = NotaryService()
    @StateObject private var documentOpenCoordinator = DocumentOpenCoordinator()
    
    var body: some Scene {
        Window("DKST macOS Notary", id: "main") {
            MainView()
                .environmentObject(notaryService)
                .environmentObject(documentOpenCoordinator)
                .frame(minWidth: AppLayout.windowMinimumWidth, minHeight: 700)
                .background(VisualEffectView().ignoresSafeArea())
                .onOpenURL { url in
                    documentOpenCoordinator.open(url)
                }
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}

// Helper view to enable system glassmorphism (ultra-thin material) behind the sidebar/window
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .sidebar
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
