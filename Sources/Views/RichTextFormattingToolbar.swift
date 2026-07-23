import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class RichTextEditingContext: ObservableObject {
    @Published private(set) var isBold = false
    @Published private(set) var isItalic = false
    @Published private(set) var isUnderlined = false
    @Published private(set) var isStruckThrough = false
    @Published private(set) var fontFamily = NSFont.systemFont(ofSize: 12).familyName ?? "Helvetica"
    @Published private(set) var fontSize: CGFloat = 12
    @Published private(set) var foregroundColor = NSColor.textColor
    @Published private(set) var backgroundColor = NSColor.clear
    @Published private(set) var alignment = NSTextAlignment.left
    @Published private(set) var lineHeightMultiple: CGFloat = 1
    @Published private(set) var errorMessage: String?

    private weak var textView: NSTextView?

    func connect(to textView: NSTextView) {
        guard self.textView !== textView else { return }
        self.textView = textView
        refresh(from: textView)
    }

    func disconnect(from textView: NSTextView) {
        guard self.textView === textView else { return }
        self.textView = nil
    }

    func refresh(from textView: NSTextView) {
        guard self.textView === textView else { return }

        let attributes = currentAttributes(in: textView)
        let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 12)
        let traits = NSFontManager.shared.traits(of: font)
        let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle

        isBold = selectionHasFontTrait(.boldFontMask, in: textView, fallback: traits.contains(.boldFontMask))
        isItalic = selectionHasFontTrait(.italicFontMask, in: textView, fallback: traits.contains(.italicFontMask))
        isUnderlined = selectionHasAttribute(.underlineStyle, in: textView) {
            Self.integerValue($0) != 0
        }
        isStruckThrough = selectionHasAttribute(.strikethroughStyle, in: textView) {
            Self.integerValue($0) != 0
        }
        fontFamily = font.familyName ?? font.fontName
        fontSize = font.pointSize
        foregroundColor = attributes[.foregroundColor] as? NSColor ?? .textColor
        backgroundColor = attributes[.backgroundColor] as? NSColor ?? .clear
        alignment = paragraphStyle?.alignment ?? .left
        lineHeightMultiple = max(paragraphStyle?.lineHeightMultiple ?? 0, 1)
    }

    func toggleBold() {
        toggleFontTrait(.boldFontMask, isCurrentlyEnabled: isBold, actionName: "Bold")
    }

    func toggleItalic() {
        toggleFontTrait(.italicFontMask, isCurrentlyEnabled: isItalic, actionName: "Italic")
    }

    func toggleUnderline() {
        toggleAttribute(
            .underlineStyle,
            isCurrentlyEnabled: isUnderlined,
            enabledValue: NSUnderlineStyle.single.rawValue,
            actionName: "Underline"
        )
    }

    func toggleStrikethrough() {
        toggleAttribute(
            .strikethroughStyle,
            isCurrentlyEnabled: isStruckThrough,
            enabledValue: NSUnderlineStyle.single.rawValue,
            actionName: "Strikethrough"
        )
    }

    func setFontFamily(_ family: String) {
        applyFont(actionName: "Font") { font in
            NSFontManager.shared.convert(font, toFamily: family)
        }
    }

    func setFontSize(_ size: CGFloat) {
        guard size >= 6, size <= 288 else { return }
        applyFont(actionName: "Font Size") { font in
            NSFontManager.shared.convert(font, toSize: size)
        }
    }

    func setForegroundColor(_ color: NSColor) {
        applyAttribute(.foregroundColor, value: color, actionName: "Text Color")
    }

    func setBackgroundColor(_ color: NSColor) {
        if color.alphaComponent < 0.01 {
            applyAttribute(.backgroundColor, value: nil, actionName: "Text Background Color")
        } else {
            applyAttribute(.backgroundColor, value: color, actionName: "Text Background Color")
        }
    }

    func setAlignment(_ alignment: NSTextAlignment) {
        applyParagraphStyle(actionName: "Alignment") { style in
            style.alignment = alignment
        }
    }

    func setLineHeightMultiple(_ multiple: CGFloat) {
        applyParagraphStyle(actionName: "Line Spacing") { style in
            style.lineHeightMultiple = multiple
        }
    }

    func showListPanel() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.orderFrontListPanel(nil)
    }

    func chooseAndInsertImage() {
        guard let textView else { return }

        let panel = NSOpenPanel()
        panel.title = "Insert Image"
        panel.prompt = "Insert"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if let window = textView.window {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                self?.insertImage(from: url)
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            insertImage(from: url)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func toggleFontTrait(
        _ trait: NSFontTraitMask,
        isCurrentlyEnabled: Bool,
        actionName: String
    ) {
        applyFont(actionName: actionName) { font in
            if isCurrentlyEnabled {
                return NSFontManager.shared.convert(font, toNotHaveTrait: trait)
            }
            return NSFontManager.shared.convert(font, toHaveTrait: trait)
        }
    }

    private func applyFont(actionName: String, transform: @escaping (NSFont) -> NSFont) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let range = textView.selectedRange()

        if range.length == 0 {
            var attributes = textView.typingAttributes
            let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 12)
            attributes[.font] = transform(font)
            textView.typingAttributes = attributes
            refresh(from: textView)
            return
        }

        performDocumentMutation(in: range, actionName: actionName) { storage in
            var runs: [(NSRange, NSFont)] = []
            storage.enumerateAttribute(.font, in: range) { value, effectiveRange, _ in
                runs.append((effectiveRange, value as? NSFont ?? NSFont.systemFont(ofSize: 12)))
            }
            for (effectiveRange, font) in runs {
                storage.addAttribute(.font, value: transform(font), range: effectiveRange)
            }
        }
    }

    private func toggleAttribute(
        _ key: NSAttributedString.Key,
        isCurrentlyEnabled: Bool,
        enabledValue: Any,
        actionName: String
    ) {
        applyAttribute(
            key,
            value: isCurrentlyEnabled ? nil : enabledValue,
            actionName: actionName
        )
    }

    private func applyAttribute(
        _ key: NSAttributedString.Key,
        value: Any?,
        actionName: String
    ) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let range = textView.selectedRange()

        if range.length == 0 {
            var attributes = textView.typingAttributes
            if let value {
                attributes[key] = value
            } else {
                attributes.removeValue(forKey: key)
            }
            textView.typingAttributes = attributes
            refresh(from: textView)
            return
        }

        performDocumentMutation(in: range, actionName: actionName) { storage in
            if let value {
                storage.addAttribute(key, value: value, range: range)
            } else {
                storage.removeAttribute(key, range: range)
            }
        }
    }

    private func applyParagraphStyle(
        actionName: String,
        update: @escaping (NSMutableParagraphStyle) -> Void
    ) {
        guard let textView, let storage = textView.textStorage else { return }
        textView.window?.makeFirstResponder(textView)

        guard storage.length > 0 else {
            var attributes = textView.typingAttributes
            let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy()
                as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            update(style)
            attributes[.paragraphStyle] = style
            textView.typingAttributes = attributes
            refresh(from: textView)
            return
        }

        let selectedRange = textView.selectedRange()
        let paragraphRange = (storage.string as NSString).paragraphRange(for: selectedRange)
        performDocumentMutation(in: paragraphRange, actionName: actionName) { storage in
            var runs: [(NSRange, NSMutableParagraphStyle)] = []
            storage.enumerateAttribute(.paragraphStyle, in: paragraphRange) { value, effectiveRange, _ in
                let style = (value as? NSParagraphStyle)?.mutableCopy()
                    as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                update(style)
                runs.append((effectiveRange, style))
            }
            for (effectiveRange, style) in runs {
                storage.addAttribute(.paragraphStyle, value: style, range: effectiveRange)
            }
        }
    }

    private func performDocumentMutation(
        in range: NSRange,
        actionName: String,
        mutation: (NSTextStorage) -> Void
    ) {
        guard let textView, let storage = textView.textStorage,
              range.location != NSNotFound, NSMaxRange(range) <= storage.length else { return }

        let previousValue = storage.attributedSubstring(from: range)
        textView.undoManager?.registerUndo(withTarget: self) { target in
            target.restore(previousValue, in: range, actionName: actionName)
        }
        textView.undoManager?.setActionName(actionName)

        storage.beginEditing()
        mutation(storage)
        storage.endEditing()
        textView.didChangeText()
        refresh(from: textView)
    }

    private func restore(_ value: NSAttributedString, in range: NSRange, actionName: String) {
        guard let textView, let storage = textView.textStorage,
              NSMaxRange(range) <= storage.length else { return }

        let redoValue = storage.attributedSubstring(from: range)
        textView.undoManager?.registerUndo(withTarget: self) { target in
            target.restore(redoValue, in: range, actionName: actionName)
        }
        textView.undoManager?.setActionName(actionName)
        storage.replaceCharacters(in: range, with: value)
        textView.setSelectedRange(range)
        textView.didChangeText()
        refresh(from: textView)
    }

    private func insertImage(from url: URL) {
        guard let textView else { return }

        do {
            let textWidth = textView.textContainer?.containerSize.width ?? textView.bounds.width
            let maximumWidth = max(120, textWidth - (textView.textContainerInset.width * 2) - 12)
            let attachment = try Self.imageAttachment(from: url, maximumWidth: maximumWidth)

            textView.window?.makeFirstResponder(textView)
            textView.insertText(
                NSAttributedString(attachment: attachment),
                replacementRange: textView.selectedRange()
            )
            refresh(from: textView)
        } catch {
            errorMessage = "The selected image could not be inserted.\n\(error.localizedDescription)"
        }
    }

    static func imageAttachment(from url: URL, maximumWidth: CGFloat) throws -> NSTextAttachment {
        let data = try Data(contentsOf: url)
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let attachment = NSTextAttachment()
        attachment.contents = data
        attachment.fileType = (
            try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier
        ) ?? UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
        attachment.image = image

        let scale = min(1, maximumWidth / image.size.width)
        attachment.bounds = NSRect(
            origin: .zero,
            size: NSSize(width: image.size.width * scale, height: image.size.height * scale)
        )
        return attachment
    }

    private func currentAttributes(in textView: NSTextView) -> [NSAttributedString.Key: Any] {
        let selectedRange = textView.selectedRange()
        if selectedRange.length == 0 {
            return textView.typingAttributes
        }
        guard let storage = textView.textStorage, storage.length > 0,
              selectedRange.location != NSNotFound, selectedRange.location < storage.length else {
            return textView.typingAttributes
        }
        return storage.attributes(at: selectedRange.location, effectiveRange: nil)
    }

    private func selectionHasFontTrait(
        _ trait: NSFontTraitMask,
        in textView: NSTextView,
        fallback: Bool
    ) -> Bool {
        let range = textView.selectedRange()
        guard range.length > 0, let storage = textView.textStorage else { return fallback }

        var hasRuns = false
        var everyRunMatches = true
        storage.enumerateAttribute(.font, in: range) { value, _, stop in
            hasRuns = true
            let font = value as? NSFont ?? NSFont.systemFont(ofSize: 12)
            if !NSFontManager.shared.traits(of: font).contains(trait) {
                everyRunMatches = false
                stop.pointee = true
            }
        }
        return hasRuns && everyRunMatches
    }

    private func selectionHasAttribute(
        _ key: NSAttributedString.Key,
        in textView: NSTextView,
        predicate: (Any?) -> Bool
    ) -> Bool {
        let range = textView.selectedRange()
        guard range.length > 0, let storage = textView.textStorage else {
            return predicate(currentAttributes(in: textView)[key])
        }

        var hasRuns = false
        var everyRunMatches = true
        storage.enumerateAttribute(key, in: range) { value, _, stop in
            hasRuns = true
            if !predicate(value) {
                everyRunMatches = false
                stop.pointee = true
            }
        }
        return hasRuns && everyRunMatches
    }

    private static func integerValue(_ value: Any?) -> Int {
        if let integer = value as? Int { return integer }
        if let number = value as? NSNumber { return number.intValue }
        return 0
    }
}

private final class FixedWidthFontPopUpButton: NSPopUpButton {
    static let fixedWidth: CGFloat = 170

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width = Self.fixedWidth
        return size
    }
}

private struct LazyFontFamilyPicker: NSViewRepresentable {
    @ObservedObject var context: RichTextEditingContext

    func makeCoordinator() -> Coordinator {
        Coordinator(context: context)
    }

    func makeNSView(context: Context) -> FixedWidthFontPopUpButton {
        let button = FixedWidthFontPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.menu?.delegate = context.coordinator
        context.coordinator.button = button
        context.coordinator.updateSelection(fontFamily: self.context.fontFamily)
        return button
    }

    func updateNSView(_ button: FixedWidthFontPopUpButton, context: Context) {
        context.coordinator.context = self.context
        context.coordinator.updateSelection(fontFamily: self.context.fontFamily)
    }

    static func dismantleNSView(_ button: FixedWidthFontPopUpButton, coordinator: Coordinator) {
        button.menu?.delegate = nil
        coordinator.button = nil
    }

    final class Coordinator: NSObject, NSMenuDelegate {
        private static let availableFontFamilies = NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }

        weak var context: RichTextEditingContext?
        weak var button: NSPopUpButton?
        private var didLoadFontFamilies = false

        init(context: RichTextEditingContext) {
            self.context = context
        }

        func updateSelection(fontFamily: String) {
            guard let button else { return }

            if didLoadFontFamilies,
               let item = button.itemArray.first(where: {
                   ($0.representedObject as? String) == fontFamily
               }) {
                button.select(item)
                return
            }

            if !didLoadFontFamilies {
                button.removeAllItems()
                button.addItem(withTitle: Self.displayName(fontFamily))
                button.lastItem?.representedObject = fontFamily
                button.selectItem(at: 0)
            }
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            guard !didLoadFontFamilies, let context else { return }

            let currentFamily = context.fontFamily
            var families = Self.availableFontFamilies
            if !families.contains(currentFamily) {
                families.insert(currentFamily, at: 0)
            }

            menu.removeAllItems()
            for family in families {
                let item = NSMenuItem(
                    title: Self.displayName(family),
                    action: #selector(selectFontFamily(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = family
                menu.addItem(item)
            }
            didLoadFontFamilies = true
            updateSelection(fontFamily: currentFamily)
        }

        @objc private func selectFontFamily(_ sender: NSMenuItem) {
            guard let family = sender.representedObject as? String else { return }
            context?.setFontFamily(family)
        }

        private static func displayName(_ family: String) -> String {
            family.hasPrefix(".") ? "System Font" : family
        }
    }
}

struct RichTextFormattingToolbar: View {
    @ObservedObject var context: RichTextEditingContext

    private let fontSizes: [CGFloat] = [
        9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32, 36, 48, 64, 72
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                styleControls
                toolbarDivider
                colorControls
                toolbarDivider
                fontControls
                toolbarDivider
                alignmentControls
                toolbarDivider

                Button {
                    context.showListPanel()
                } label: {
                    Image(systemName: "list.bullet")
                        .frame(width: 18)
                }
                .help("Lists")

                lineSpacingControl
                toolbarDivider

                Button {
                    context.chooseAndInsertImage()
                } label: {
                    Label("Image", systemImage: "photo")
                }
                .help("Insert Image")
            }
            .controlSize(.small)
            .padding(.vertical, 2)
        }
        .alert(
            "Unable to Insert Image",
            isPresented: Binding(
                get: { context.errorMessage != nil },
                set: { if !$0 { context.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                context.clearError()
            }
        } message: {
            Text(context.errorMessage ?? "")
        }
    }

    private var styleControls: some View {
        HStack(spacing: 3) {
            Toggle(isOn: toggleBinding(isOn: context.isBold, action: context.toggleBold)) {
                Text("B").bold().frame(width: 16)
            }
            .keyboardShortcut("b", modifiers: .command)
            .help("Bold")

            Toggle(isOn: toggleBinding(isOn: context.isItalic, action: context.toggleItalic)) {
                Text("I").italic().frame(width: 16)
            }
            .keyboardShortcut("i", modifiers: .command)
            .help("Italic")

            Toggle(isOn: toggleBinding(isOn: context.isUnderlined, action: context.toggleUnderline)) {
                Text("U").underline().frame(width: 16)
            }
            .keyboardShortcut("u", modifiers: .command)
            .help("Underline")

            Toggle(isOn: toggleBinding(isOn: context.isStruckThrough, action: context.toggleStrikethrough)) {
                Text("S").strikethrough().frame(width: 16)
            }
            .help("Strikethrough")
        }
        .toggleStyle(.button)
    }

    private var colorControls: some View {
        HStack(spacing: 4) {
            ColorPicker(
                "Text Color",
                selection: Binding(
                    get: { Color(nsColor: context.foregroundColor) },
                    set: { context.setForegroundColor(NSColor($0)) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .help("Text Color")

            ColorPicker(
                "Text Background Color",
                selection: Binding(
                    get: { Color(nsColor: context.backgroundColor) },
                    set: { context.setBackgroundColor(NSColor($0)) }
                )
            )
            .labelsHidden()
            .help("Text Background Color")
        }
        .frame(width: 62)
    }

    private var fontControls: some View {
        HStack(spacing: 6) {
            LazyFontFamilyPicker(context: context)
            .frame(width: 170)
            .help("Font")

            Menu {
                ForEach(fontSizes, id: \.self) { size in
                    Button(Self.displaySize(size)) {
                        context.setFontSize(size)
                    }
                }
            } label: {
                Text(Self.displaySize(context.fontSize))
                    .monospacedDigit()
                .frame(minWidth: 48)
            }
            .help("Font Size")
        }
    }

    private var alignmentControls: some View {
        HStack(spacing: 3) {
            alignmentToggle(.left, systemName: "text.alignleft", help: "Align Left")
            alignmentToggle(.center, systemName: "text.aligncenter", help: "Align Center")
            alignmentToggle(.right, systemName: "text.alignright", help: "Align Right")
            alignmentToggle(.justified, systemName: "text.justify", help: "Justify")
        }
        .toggleStyle(.button)
    }

    private var lineSpacingControl: some View {
        Menu {
            ForEach([1.0, 1.15, 1.5, 2.0], id: \.self) { spacing in
                Button(String(format: "%.2g", spacing)) {
                    context.setLineHeightMultiple(spacing)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal")
                Text(String(format: "%.1f", context.lineHeightMultiple))
                    .monospacedDigit()
            }
        }
        .help("Line Spacing")
    }

    private var toolbarDivider: some View {
        Divider()
            .frame(height: 22)
            .padding(.horizontal, 2)
    }

    private func alignmentToggle(
        _ alignment: NSTextAlignment,
        systemName: String,
        help: String
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: { context.alignment == alignment },
                set: { isOn in
                    if isOn {
                        context.setAlignment(alignment)
                    }
                }
            )
        ) {
            Image(systemName: systemName)
                .frame(width: 18)
        }
        .help(help)
    }

    private func toggleBinding(isOn: Bool, action: @escaping () -> Void) -> Binding<Bool> {
        Binding(
            get: { isOn },
            set: { _ in action() }
        )
    }

    private static func displaySize(_ size: CGFloat) -> String {
        size.rounded() == size ? String(Int(size)) : String(format: "%.1f", size)
    }
}
