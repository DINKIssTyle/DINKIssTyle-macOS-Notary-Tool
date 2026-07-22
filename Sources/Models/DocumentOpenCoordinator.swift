import Foundation

final class DocumentOpenCoordinator: ObservableObject {
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let url: URL
    }

    @Published private(set) var request: Request?

    func open(_ url: URL) {
        guard url.pathExtension.lowercased() == "dnt" else { return }
        request = Request(url: url.standardizedFileURL)
    }

    @discardableResult
    func consume(_ id: UUID) -> Request? {
        guard request?.id == id else { return nil }
        let consumedRequest = request
        request = nil
        return consumedRequest
    }
}
