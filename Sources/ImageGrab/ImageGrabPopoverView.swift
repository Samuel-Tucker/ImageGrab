import SwiftUI
import UniformTypeIdentifiers

struct ImageGrabPopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel
    let onClose: () -> Void
    @State private var copiedID: UUID?
    @State private var showClearAllConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ImageGrab")
                    .font(.headline)
                Text("Opt+G")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Opt+Cmd+G")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(viewModel.entries.count) captures")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    Text("Press Opt+G for region or Opt+Cmd+G for full screen")
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

            Divider()

            // Footer — pill-style buttons with SF Symbols
            HStack {
                Button {
                    viewModel.openFolder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text("Open Folder")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    showClearAllConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("Clear All")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
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
    }

    @ViewBuilder
    private func captureCell(_ entry: CaptureEntry) -> some View {
        CaptureCell(
            entry: entry,
            viewModel: viewModel,
            isCopied: copiedID == entry.id,
            onCopy: { copyPath(for: entry) },
            onQuickView: { viewModel.showQuickView(for: entry) },
            onEdit: { viewModel.editAnnotations(for: entry) },
            onDelete: { viewModel.delete(id: entry.id) },
            onRename: { newName in viewModel.rename(id: entry.id, to: newName) }
        )
    }

    private func copyPath(for entry: CaptureEntry) {
        viewModel.copyPath(for: entry)
        copiedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if copiedID == entry.id { copiedID = nil }
        }
    }
}

// MARK: - CaptureCell (async thumbnail loading)

private struct CaptureCell: View {
    let entry: CaptureEntry
    let viewModel: PopoverViewModel
    let isCopied: Bool
    let onCopy: () -> Void
    let onQuickView: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Bool

    @State private var thumbnail: NSImage?
    @State private var showDeleteConfirm = false
    @State private var isPreviewHovered = false
    @State private var isCopyHovered = false
    @State private var isEditingName = false
    @State private var isRenameHovered = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail with copy bar and quick view button
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
                        .stroke(isCopied ? Color.green : Color.clear, lineWidth: 2)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onDrag {
                    dragProvider()
                }

                VStack {
                    HStack {
                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.black.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                        .help("Edit annotations")

                        Spacer()

                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.black.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                        .help("Delete capture")
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
                    }
                    .padding(4)

                    Spacer()
                }
            }

            HStack(spacing: 6) {
                Button {
                    onQuickView()
                } label: {
                    Label("Preview", systemImage: "eye")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isPreviewHovered ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isPreviewHovered ? Color.secondary.opacity(0.24) : Color.secondary.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onHover { isPreviewHovered = $0 }
                .help("Preview capture")

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
            }

            // Name row with inline rename
            HStack(spacing: 4) {
                if isEditingName {
                    TextField("", text: $draftName, onCommit: commitRename)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 9))
                        .focused($nameFieldFocused)
                    Button {
                        commitRename()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("Save name")
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
                onEdit()
            } label: {
                Label("Edit Annotations", systemImage: "pencil")
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
        viewModel.onDragStarted?()

        let url = viewModel.dragURL(for: entry)
        let provider = NSItemProvider()
        provider.suggestedName = url.lastPathComponent

        let imageType = UTType(filenameExtension: url.pathExtension) ?? .png

        // File URL for Muxary raw/readable terminal panes and Electron/browser drop targets.
        provider.registerObject(url as NSURL, visibility: .all)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            visibility: .all
        ) { completion in
            completion(url.absoluteString.data(using: .utf8), nil)
            return nil
        }
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.url.identifier,
            visibility: .all
        ) { completion in
            completion(url.absoluteString.data(using: .utf8), nil)
            return nil
        }

        // Raw image data for apps that accept image data directly.
        provider.registerDataRepresentation(
            forTypeIdentifier: imageType.identifier,
            visibility: .all
        ) { completion in
            do {
                let imageData = try Data(contentsOf: url)
                completion(imageData, nil)
            } catch {
                completion(nil, error)
            }
            return nil
        }
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.image.identifier,
            visibility: .all
        ) { completion in
            do {
                let imageData = try Data(contentsOf: url)
                completion(imageData, nil)
            } catch {
                completion(nil, error)
            }
            return nil
        }

        // File representation for file-system-aware apps (Finder, etc.).
        provider.registerFileRepresentation(
            forTypeIdentifier: imageType.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(url, false, nil)
            return nil
        }

        // Plain text path for readable terminal/chat inputs.
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier,
            visibility: .all
        ) { completion in
            completion(url.path.data(using: .utf8), nil)
            return nil
        }

        return provider
    }
}
