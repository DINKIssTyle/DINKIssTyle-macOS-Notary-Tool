import SwiftUI

@main
struct NotaryApp: App {
    // Create NotaryService as a shared environment object
    @StateObject private var notaryService = NotaryService()
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(notaryService)
                .frame(minWidth: AppLayout.windowMinimumWidth, minHeight: 700)
                .background(VisualEffectView().ignoresSafeArea())
        }
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
