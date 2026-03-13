import SwiftUI
import UniformTypeIdentifiers

struct ImageGrabPopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel
    @State private var editingID: UUID?
    @State private var editText = ""
    @State private var copiedID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ImageGrab")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.entries.count) captures")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    Text("Copy an image, then press ctl+opt+G")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.fixed(130)),
                        GridItem(.fixed(130))
                    ], spacing: 8) {
                        ForEach(viewModel.entries) { entry in
                            captureCell(entry)
                        }
                    }
                    .padding(8)
                }
            }

            Divider()

            // Footer
            HStack {
                Button("Open Folder") {
                    viewModel.openFolder()
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Spacer()

                Button("Clear All") {
                    viewModel.clearAll()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 300, height: 400)
    }

    @ViewBuilder
    private func captureCell(_ entry: CaptureEntry) -> some View {
        VStack(spacing: 4) {
            // Thumbnail
            if let thumb = viewModel.thumbnailImage(for: entry) {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(copiedID == entry.id ? Color.green : Color.clear, lineWidth: 2)
                    )
                    .onTapGesture {
                        viewModel.copyPath(for: entry)
                        copiedID = entry.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            if copiedID == entry.id { copiedID = nil }
                        }
                    }
                    .contextMenu {
                        Button {
                            viewModel.copyPath(for: entry)
                            copiedID = entry.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                if copiedID == entry.id { copiedID = nil }
                            }
                        } label: {
                            Label("Copy Path", systemImage: "doc.on.doc")
                        }
                        Button {
                            let path = viewModel.fullPath(for: entry)
                            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                        Button {
                            editingID = entry.id
                            editText = (entry.filename as NSString).deletingPathExtension
                        } label: {
                            Label("Edit Name", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive) {
                            viewModel.delete(id: entry.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .onDrag {
                        let url = URL(fileURLWithPath: viewModel.fullPath(for: entry))
                        let provider = NSItemProvider()
                        provider.suggestedName = entry.filename

                        // Register raw PNG data for apps that accept image data
                        // directly (browsers, Electron apps like Claude desktop)
                        if let imageData = try? Data(contentsOf: url) {
                            provider.registerDataRepresentation(
                                forTypeIdentifier: UTType.png.identifier,
                                visibility: .all
                            ) { completion in
                                completion(imageData, nil)
                                return nil
                            }
                        }

                        // Register as file for file-system-aware apps (Finder, etc.)
                        provider.registerFileRepresentation(
                            forTypeIdentifier: UTType.png.identifier,
                            fileOptions: [],
                            visibility: .all
                        ) { completion in
                            completion(url, false, nil)
                            return nil
                        }
                        return provider
                    }
            }

            // Name
            if editingID == entry.id {
                TextField("Name", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 9))
                    .frame(width: 120)
                    .onSubmit {
                        if !editText.isEmpty {
                            viewModel.rename(id: entry.id, to: editText)
                        }
                        editingID = nil
                    }
            } else {
                HStack(spacing: 2) {
                    if entry.aiNamed {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    Text((entry.filename as NSString).deletingPathExtension)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .onTapGesture {
                            editingID = entry.id
                            editText = (entry.filename as NSString).deletingPathExtension
                        }
                }
            }

            // Copy Path button
            Button {
                viewModel.copyPath(for: entry)
                copiedID = entry.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if copiedID == entry.id { copiedID = nil }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 8))
                    Text(copiedID == entry.id ? "Copied!" : "Copy Path")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(copiedID == entry.id ? .green : .accentColor)
            }
            .buttonStyle(.borderless)
        }
    }
}
