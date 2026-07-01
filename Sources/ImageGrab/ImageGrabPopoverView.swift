import SwiftUI
import UniformTypeIdentifiers

struct ImageGrabPopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel
    let onClose: () -> Void
    @State private var copiedID: UUID?
    @State private var copiedTextID: UUID?
    @State private var noTextID: UUID?
    @State private var recognizingTextID: UUID?
    @State private var showClearAllConfirm = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var copiedSelection = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ImageGrab")
                    .font(.headline)
                Button {} label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Ctrl+Cmd+G: region capture\nOpt+G: legacy region capture\nOpt+Cmd+G: full screen capture")
                Spacer()
                Text("\(viewModel.entries.count) captures")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    viewModel.togglePopoverPinned()
                } label: {
                    Image(systemName: viewModel.isPopoverPinned ? "pin.fill" : "pin")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(viewModel.isPopoverPinned ? Color.accentColor : .secondary)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(viewModel.isPopoverPinned ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .help(viewModel.isPopoverPinned ? "Sticky on: ImageGrab stays open until you close it" : "Keep ImageGrab open while dragging multiple captures")
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Hide ImageGrab")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if viewModel.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No captures yet")
                        .foregroundStyle(.secondary)
                    Text("Press Ctrl+Cmd+G for region or Opt+Cmd+G for full screen")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 10) {
                        ForEach(viewModel.entries) { entry in
                            captureCell(entry)
                        }
                    }
                    .padding(8)
                }
            }

            if !selectedIDs.isEmpty {
                Divider()

                HStack(spacing: 8) {
                    Text("\(selectedIDs.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        selectedIDs.removeAll()
                        copiedSelection = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Clear selection")

                    Button {
                        copySelectedCaptures()
                    } label: {
                        Label(copiedSelection ? "Copied" : "Copy All", systemImage: copiedSelection ? "checkmark" : "doc.on.clipboard")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(copiedSelection ? Color.green.opacity(0.82) : Color.accentColor.opacity(0.82))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Copy selected captures so they can be pasted")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()

            // Footer actions stay low-emphasis so capture actions remain primary.
            HStack(spacing: 6) {
                Button {
                    viewModel.openFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .help("Open captures folder")

                Button {
                    viewModel.repeatLastRegion()
                } label: {
                    Image(systemName: "repeat")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(viewModel.canRepeatLastRegion ? Color.accentColor : .secondary)
                        .frame(width: 28, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(viewModel.canRepeatLastRegion ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canRepeatLastRegion)
                .help(viewModel.canRepeatLastRegion ? "Repeat last selected region" : "Select a region once to enable repeat capture")

                Menu {
                    ForEach(CaptureDelay.allCases) { option in
                        Button {
                            viewModel.captureDelay = option
                        } label: {
                            if viewModel.captureDelay == option {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    Label(viewModel.captureDelay.label, systemImage: "timer")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(viewModel.captureDelay == .none ? .secondary : Color.accentColor)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(viewModel.captureDelay == .none ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.16))
                        )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Delay before the next capture begins")

                Spacer()

                Button {
                    showClearAllConfirm = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.red.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
                .help("Delete all captures")
                .confirmationDialog(
                    "Delete all captures?",
                    isPresented: $showClearAllConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Clear All", role: .destructive) {
                        viewModel.clearAll()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This action cannot be undone.")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 300, height: 400)
        .onChange(of: viewModel.entries.map(\.id)) { ids in
            selectedIDs.formIntersection(Set(ids))
            if selectedIDs.isEmpty {
                copiedSelection = false
            }
        }
    }

    @ViewBuilder
    private func captureCell(_ entry: CaptureEntry) -> some View {
        CaptureCell(
            entry: entry,
            viewModel: viewModel,
            isCopied: copiedID == entry.id,
            isTextCopied: copiedTextID == entry.id,
            isNoText: noTextID == entry.id,
            isRecognizingText: recognizingTextID == entry.id,
            isSelected: selectedIDs.contains(entry.id),
            onCopy: { copyPath(for: entry) },
            onCopyText: { copyText(for: entry) },
            onQuickView: { viewModel.showQuickView(for: entry) },
            onEdit: { viewModel.editAnnotations(for: entry) },
            onToggleSelected: { toggleSelection(for: entry) },
            onDelete: {
                selectedIDs.remove(entry.id)
                viewModel.delete(id: entry.id)
            },
            onRename: { newName in viewModel.rename(id: entry.id, to: newName) }
        )
    }

    private func toggleSelection(for entry: CaptureEntry) {
        if selectedIDs.contains(entry.id) {
            selectedIDs.remove(entry.id)
        } else {
            selectedIDs.insert(entry.id)
        }
        copiedSelection = false
    }

    private func copySelectedCaptures() {
        let selectedEntries = viewModel.entries.filter { selectedIDs.contains($0.id) }
        guard viewModel.copyImages(for: selectedEntries) else { return }

        copiedSelection = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            copiedSelection = false
        }
    }

    private func copyPath(for entry: CaptureEntry) {
        viewModel.copyPath(for: entry)
        copiedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if copiedID == entry.id { copiedID = nil }
        }
    }

    private func copyText(for entry: CaptureEntry) {
        guard recognizingTextID == nil else { return }
        recognizingTextID = entry.id
        copiedTextID = nil
        noTextID = nil

        Task {
            let success = await viewModel.copyText(for: entry)
            recognizingTextID = nil
            if success {
                copiedTextID = entry.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if copiedTextID == entry.id { copiedTextID = nil }
                }
            } else {
                noTextID = entry.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if noTextID == entry.id { noTextID = nil }
                }
            }
        }
    }
}

// MARK: - CaptureCell (async thumbnail loading)

private struct CaptureCell: View {
    let entry: CaptureEntry
    let viewModel: PopoverViewModel
    let isCopied: Bool
    let isTextCopied: Bool
    let isNoText: Bool
    let isRecognizingText: Bool
    let isSelected: Bool
    let onCopy: () -> Void
    let onCopyText: () -> Void
    let onQuickView: () -> Void
    let onEdit: () -> Void
    let onToggleSelected: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Bool

    @State private var thumbnail: NSImage?
    @State private var showDeleteConfirm = false
    @State private var isCellHovered = false
    @State private var hoveredOverlayAction: ThumbnailAction?
    @State private var isCopyHovered = false
    @State private var isFullWidthCopyTextHovered = false
    @State private var isEditingName = false
    @State private var isRenameHovered = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    fileprivate enum ThumbnailAction: Hashable {
        case preview, copyText, edit, delete
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(thumbnailBorderColor, lineWidth: thumbnailBorderWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onDrag {
                    dragProvider()
                }

                VStack {
                    HStack {
                        Spacer()

                        HStack(spacing: 4) {
                            thumbnailActionButton(
                                systemName: "eye",
                                help: "Preview capture",
                                isHovered: hoveredOverlayAction == .preview,
                                action: onQuickView
                            )
                            .onHover { setHoveredOverlayAction(.preview, hovering: $0) }

                            thumbnailActionButton(
                                systemName: isRecognizingText ? "hourglass" : "text.viewfinder",
                                help: isRecognizingText ? "Recognizing text" : "Copy text from capture",
                                isHovered: hoveredOverlayAction == .copyText,
                                action: onCopyText
                            )
                            .disabled(isRecognizingText)
                            .onHover { setHoveredOverlayAction(.copyText, hovering: $0) }

                            thumbnailActionButton(
                                systemName: "scribble.variable",
                                help: "Edit annotations",
                                isHovered: hoveredOverlayAction == .edit,
                                action: onEdit
                            )
                            .onHover { setHoveredOverlayAction(.edit, hovering: $0) }

                            thumbnailActionButton(
                                systemName: "trash",
                                help: "Delete capture",
                                isHovered: hoveredOverlayAction == .delete,
                                isDestructive: true,
                                action: { showDeleteConfirm = true }
                            )
                            .onHover { setHoveredOverlayAction(.delete, hovering: $0) }
                            .confirmationDialog(
                                "Delete this capture?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible
                            ) {
                                Button("Delete", role: .destructive) {
                                    onDelete()
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("This action cannot be undone.")
                            }

                            selectionButton
                        }
                        .opacity(isCellHovered ? 1 : 0)
                        .allowsHitTesting(isCellHovered)
                        .animation(.easeOut(duration: 0.12), value: isCellHovered)
                    }
                    .padding(4)

                    Spacer()
                }

                VStack {
                    HStack {
                        Spacer()
                        selectionButton
                            .opacity(isCellHovered ? 0 : 1)
                    }
                    .padding(4)

                    Spacer()
                }

                // Transient helper text for the currently-hovered overlay button.
                // Lives inside the thumbnail so it disappears with the icon strip
                // and never adds permanent vertical clutter.
                if let label = hoveredOverlayActionLabel {
                    VStack {
                        Spacer()
                        Text(label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.78))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .padding(.bottom, 6)
                    }
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: hoveredOverlayAction)

            Button {
                onCopy()
            } label: {
                Label(isCopied ? "Copied" : "Copy Path", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(copyButtonBackground)
                    )
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { isCopyHovered = $0 }
            .help("Copy capture path")

            Button {
                onCopyText()
            } label: {
                Label(copyTextTitle, systemImage: copyTextIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(copyTextButtonBackground)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isRecognizingText)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { isFullWidthCopyTextHovered = $0 }
            .help("Copy detected text from capture")

            // Name row with inline rename
            HStack(spacing: 4) {
                if isEditingName {
                    TextField("", text: $draftName, onCommit: commitRename)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 9))
                        .focused($nameFieldFocused)
                        .onExitCommand(perform: cancelRename)
                    Button {
                        cancelRename()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel")
                } else {
                    Text((entry.filename as NSString).deletingPathExtension)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        startRename()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isRenameHovered ? Color.accentColor : Color.secondary)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isRenameHovered ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .onHover { isRenameHovered = $0 }
                    .help("Rename capture")
                }
            }
        }
        .contextMenu {
            Button {
                onQuickView()
            } label: {
                Label("Preview", systemImage: "eye")
            }
            Button {
                onCopy()
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            Button {
                onCopyText()
            } label: {
                Label("Copy Text", systemImage: "text.viewfinder")
            }
            .disabled(isRecognizingText)
            Button {
                onEdit()
            } label: {
                Label("Edit Annotations", systemImage: "scribble.variable")
            }
            Button {
                let path = viewModel.fullPath(for: entry)
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            Button {
                startRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                onToggleSelected()
            } label: {
                Label(isSelected ? "Deselect" : "Select", systemImage: isSelected ? "checkmark.square.fill" : "square")
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .task(id: entry.filename) {
            thumbnail = await viewModel.thumbnailImage(for: entry)
        }
        .onHover { isCellHovered = $0 }
    }

    private func thumbnailActionButton(
        systemName: String,
        help: String,
        isHovered: Bool,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isDestructive && isHovered ? Color.red : Color.white)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.black.opacity(0.76) : Color.black.opacity(0.56))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(isHovered ? 0.30 : 0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .help(help)
    }

    private var selectionButton: some View {
        Button(action: onToggleSelected) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.white)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(isSelected ? 0.78 : 0.56))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(isSelected ? 0.34 : 0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .help(isSelected ? "Deselect capture" : "Select capture for Copy All")
    }

    private var thumbnailBorderColor: Color {
        if isCopied { return Color.green }
        if isSelected { return Color.accentColor }
        return Color.clear
    }

    private var thumbnailBorderWidth: CGFloat {
        isCopied || isSelected ? 2 : 0
    }

    private var copyButtonBackground: Color {
        if isCopyHovered {
            return Color.black.opacity(0.78)
        }
        if isCopied {
            return Color.green.opacity(0.82)
        }
        return Color.accentColor.opacity(0.82)
    }

    private var copyTextTitle: String {
        if isRecognizingText { return "Reading Text" }
        if isTextCopied { return "Text Copied" }
        if isNoText { return "No Text" }
        return "Copy Text"
    }

    private var copyTextIcon: String {
        if isRecognizingText { return "hourglass" }
        if isTextCopied { return "checkmark" }
        if isNoText { return "exclamationmark.triangle" }
        return "text.viewfinder"
    }

    private var copyTextButtonBackground: Color {
        if isNoText { return Color.orange.opacity(0.86) }
        if isTextCopied { return Color.green.opacity(0.82) }
        if isFullWidthCopyTextHovered || isRecognizingText { return Color.black.opacity(0.78) }
        return Color.blue.opacity(0.82)
    }

    private var hoveredOverlayActionLabel: String? {
        guard isCellHovered, let action = hoveredOverlayAction else { return nil }
        switch action {
        case .preview:
            return "Preview"
        case .copyText:
            if isRecognizingText { return "Reading Text…" }
            if isTextCopied { return "Text Copied" }
            if isNoText { return "No Text Found" }
            return "Copy Text"
        case .edit:
            return "Edit Annotations"
        case .delete:
            return "Delete"
        }
    }

    private func setHoveredOverlayAction(_ action: ThumbnailAction, hovering: Bool) {
        if hovering {
            hoveredOverlayAction = action
        } else if hoveredOverlayAction == action {
            hoveredOverlayAction = nil
        }
    }

    private func startRename() {
        draftName = (entry.filename as NSString).deletingPathExtension
        isEditingName = true
        DispatchQueue.main.async { nameFieldFocused = true }
    }

    private func commitRename() {
        let proposed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = (entry.filename as NSString).deletingPathExtension
        guard !proposed.isEmpty, proposed != current else {
            cancelRename()
            return
        }
        if !onRename(proposed) {
            NSSound.beep()
        }
        isEditingName = false
        nameFieldFocused = false
    }

    private func cancelRename() {
        isEditingName = false
        nameFieldFocused = false
        draftName = ""
    }

    private func dragProvider() -> NSItemProvider {
        viewModel.makeDragProvider(for: entry)
    }
}
