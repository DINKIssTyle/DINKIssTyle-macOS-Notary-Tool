import SwiftUI

enum AppLayout {
    static let navigationSidebarWidth: CGFloat = 240
    static let workPanelWidth: CGFloat = 420
    static let workAreaMinimumWidth: CGFloat = 800
    static let windowMinimumWidth: CGFloat = 1060
}

struct MainView: View {
    @State private var selectedTab: Tab = .notarize
    
    enum Tab: String, CaseIterable, Identifiable {
        case notarize = "Notarize"
        case credentials = "Notary Profiles"
        
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .notarize: return "lock.shield.fill"
            case .credentials: return "key.fill"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 20) {
                // App Logo and Title
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DKST")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text("macOS Notary")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                
                // Sidebar Navigation Links
                List(selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        HStack(spacing: 10) {
                            Image(systemName: tab.icon)
                                .font(.body)
                                .frame(width: 20)
                            Text(tab.rawValue)
                                .font(.body)
                        }
                        .padding(.vertical, 6)
                        .tag(tab)
                    }
                }
                .listStyle(.sidebar)
                
                Spacer()
                
                // Footer
                VStack(alignment: .leading, spacing: 4) {
                    Text("v1.0.0")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Local Notarization Flow")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationSplitViewColumnWidth(
                min: AppLayout.navigationSidebarWidth,
                ideal: AppLayout.navigationSidebarWidth,
                max: AppLayout.navigationSidebarWidth
            )
        } detail: {
            Group {
                switch selectedTab {
                case .notarize:
                    NotaryView()
                case .credentials:
                    KeychainView()
                }
            }
            .frame(
                minWidth: AppLayout.workAreaMinimumWidth,
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .background(Color(NSColor.windowBackgroundColor).opacity(0.85))
        }
    }
}
