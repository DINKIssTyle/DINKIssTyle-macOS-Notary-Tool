import SwiftUI

enum AppLayout {
    static let navigationSidebarWidth: CGFloat = 240
    static let primaryActionWidth: CGFloat = 380
    static let workAreaMinimumWidth: CGFloat = 800
    static let windowMinimumWidth: CGFloat = 1060
}

struct EqualPanelSplitView<Leading: View, Trailing: View>: View {
    @Environment(\.displayScale) private var displayScale
    let leading: Leading
    let trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            trailing
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(width: 1 / max(displayScale, 1))
                        .frame(maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var documentOpenCoordinator: DocumentOpenCoordinator
    @State private var selectedTab: Tab = .notarize
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
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

    private var columnVisibilityWithoutAnimation: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { columnVisibility },
            set: { newValue in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    columnVisibility = newValue
                }
            }
        )
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibilityWithoutAnimation) {
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
                    Text("© 2026 DINKI'ssTyle")
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
        .navigationSplitViewStyle(.balanced)
        .onReceive(documentOpenCoordinator.$request) { request in
            if request != nil {
                selectedTab = .notarize
            }
        }
    }
}
