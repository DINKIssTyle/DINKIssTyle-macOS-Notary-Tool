import AppKit
import SwiftUI

struct RichTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var rtfData: Data?
    var isEditable = true

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        let contentSize = scrollView.contentSize
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.frame = NSRect(origin: .zero, size: contentSize)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 5, height: 5)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView

        context.coordinator.applyModel(to: textView, text: text, rtfData: rtfData)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        if rtfData != context.coordinator.lastRTFData || (rtfData == nil && textView.string != text) {
            context.coordinator.applyModel(to: textView, text: text, rtfData: rtfData)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var lastRTFData: Data?
        private var isApplyingModel = false

        init(parent: RichTextEditor) {
            self.parent = parent
        }

        func applyModel(to textView: NSTextView, text: String, rtfData: Data?) {
            isApplyingModel = true
            defer { isApplyingModel = false }

            if let rtfData,
               let attributed = attributedString(from: rtfData) {
                textView.textStorage?.setAttributedString(attributed)
                lastRTFData = rtfData
            } else {
                let attributed = NSAttributedString(
                    string: text,
                    attributes: [.font: NSFont.systemFont(ofSize: 11)]
                )
                textView.textStorage?.setAttributedString(attributed)
                lastRTFData = nil
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingModel, let textView = notification.object as? NSTextView else { return }
            let fullRange = NSRange(location: 0, length: textView.textStorage?.length ?? 0)
            var hasAttachments = false
            textView.textStorage?.enumerateAttribute(.attachment, in: fullRange) { value, _, stop in
                if value != nil {
                    hasAttachments = true
                    stop.pointee = true
                }
            }
            let documentType: NSAttributedString.DocumentType = hasAttachments ? .rtfd : .rtf
            let data = try? textView.textStorage?.data(
                from: fullRange,
                documentAttributes: [.documentType: documentType]
            )
            lastRTFData = data
            parent.text = textView.string
            parent.rtfData = data
        }

        private func attributedString(from data: Data) -> NSAttributedString? {
            let isRTFD = data.starts(with: Data("rtfd".utf8))
            let types: [NSAttributedString.DocumentType] = isRTFD ? [.rtfd, .rtf] : [.rtf, .rtfd]
            for type in types {
                if let attributed = try? NSAttributedString(
                    data: data,
                    options: [.documentType: type],
                    documentAttributes: nil
                ) {
                    return attributed
                }
            }
            return nil
        }
    }
}
