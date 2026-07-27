import SwiftUI

struct SystemReadinessView: View {
    @EnvironmentObject private var service: NotaryService

    private var isReady: Bool {
        !service.isCheckingSystemReadiness
            && !service.systemReadinessItems.isEmpty
            && !service.hasSystemReadinessIssues
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                VStack(spacing: 12) {
                    ForEach(service.systemReadinessItems) { item in
                        readinessRow(item)
                    }
                }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(28)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: isReady ? "checkmark.shield.fill" : "wrench.and.screwdriver.fill")
                .font(.system(size: 34))
                .foregroundStyle(isReady ? Color.green : Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("System Readiness")
                    .font(.title2)
                    .fontWeight(.bold)

                if service.isCheckingSystemReadiness || service.systemReadinessItems.isEmpty {
                    Text("Checking the tools and credentials used by DKST macOS Notary…")
                        .foregroundStyle(.secondary)
                } else if isReady {
                    Text("All signing, notarization, and distribution requirements are ready.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(service.systemReadinessIssueCount) item(s) need attention. Follow the instructions below, then check again.")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task {
                    await service.refreshSystemReadiness()
                }
            } label: {
                Label("Check Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(service.isCheckingSystemReadiness)
        }
    }

    private func readinessRow(_ item: SystemReadinessItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            readinessIcon(for: item.status)
                .font(.system(size: 19))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)

                Text(item.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let resolution = item.resolution,
                   item.status == .attention || item.status == .unavailable {
                    Divider()
                        .padding(.vertical, 3)

                    Label("How to fix", systemImage: "lightbulb.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)

                    Text(resolution)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor(for: item.status), lineWidth: 1)
        }
    }

    private func readinessIcon(for status: SystemReadinessStatus) -> some View {
        switch status {
        case .checking:
            return AnyView(ProgressView().controlSize(.small))
        case .ready:
            return AnyView(
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            )
        case .attention:
            return AnyView(
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            )
        case .unavailable:
            return AnyView(
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            )
        }
    }

    private func borderColor(for status: SystemReadinessStatus) -> Color {
        switch status {
        case .attention:
            return .orange.opacity(0.35)
        case .unavailable:
            return .red.opacity(0.35)
        case .checking, .ready:
            return .secondary.opacity(0.15)
        }
    }
}
