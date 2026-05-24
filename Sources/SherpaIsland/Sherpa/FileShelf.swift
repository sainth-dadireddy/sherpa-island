import Cocoa
import SwiftUI

// MARK: - Model

struct ShelfFile: Identifiable, Codable {
    let id: UUID
    let url: URL
    let name: String
    let addedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, url, name, addedAt
    }

    init(id: UUID = UUID(), url: URL, name: String, addedAt: Date = Date()) {
        self.id = id
        self.url = url
        self.name = name
        self.addedAt = addedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url.path, forKey: .url)
        try container.encode(name, forKey: .name)
        try container.encode(addedAt, forKey: .addedAt)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        let path = try container.decode(String.self, forKey: .url)
        self.url = URL(fileURLWithPath: path)
        self.name = try container.decode(String.self, forKey: .name)
        self.addedAt = try container.decode(Date.self, forKey: .addedAt)
    }
}

// MARK: - Store

@MainActor
class FileShelfStore: ObservableObject {
    @Published var files: [ShelfFile] = []

    private let maxFiles = 10
    private let persistenceURL: URL

    init() {
        let sherpaDirURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sherpa-island", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: sherpaDirURL, withIntermediateDirectories: true)

        self.persistenceURL = sherpaDirURL.appendingPathComponent("shelf.json")
        loadFromDisk()
    }

    func add(url: URL) {
        guard url.isFileURL else { return }

        let name = url.lastPathComponent
        let newFile = ShelfFile(url: url, name: name)

        // Remove duplicate if exists
        files.removeAll { $0.url == url }

        // Add to front and maintain LRU
        files.insert(newFile, at: 0)

        // Keep only max files
        if files.count > maxFiles {
            files = Array(files.prefix(maxFiles))
        }

        saveToDisk()
    }

    func remove(id: UUID) {
        files.removeAll { $0.id == id }
        saveToDisk()
    }

    func clear() {
        files.removeAll()
        saveToDisk()
    }

    func launchInFinder(id: UUID) {
        guard let file = files.first(where: { $0.id == id }) else { return }

        // Verify file still exists
        guard FileManager.default.fileExists(atPath: file.url.path) else {
            remove(id: id)
            return
        }

        NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: "")
    }

    func airdrop(id: UUID) {
        guard let file = files.first(where: { $0.id == id }) else { return }

        // Verify file still exists
        guard FileManager.default.fileExists(atPath: file.url.path) else {
            remove(id: id)
            return
        }

        if let service = NSSharingService(named: .sendViaAirDrop) {
            service.perform(withItems: [file.url])
        }
    }

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(files)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            print("Failed to save shelf: \(error)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: persistenceURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            files = try decoder.decode([ShelfFile].self, from: data)

            // Prune missing files
            files.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
        } catch {
            print("Failed to load shelf: \(error)")
        }
    }
}

// MARK: - View

struct FileShelfView: View {
    @StateObject private var store = FileShelfStore()
    @State private var isTargeted = false

    private let columns = [
        GridItem(.adaptive(minimum: 80), spacing: 12)
    ]

    var body: some View {
        ZStack {
            // Liquid Glass background
            liquidGlassBackground()

            VStack(spacing: 12) {
                HStack {
                    Text("File Shelf")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    if !store.files.isEmpty {
                        Button(action: { store.clear() }) {
                            Text("Clear All")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                if store.files.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)

                        Text("Drag files here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .foregroundColor(isTargeted ? .blue : .secondary.opacity(0.5))
                    )
                    .padding(12)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.files) { file in
                            FileShelfItemView(file: file, store: store)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                return handleDrop(providers)
            }
        }
        .frame(minHeight: 200)
        .cornerRadius(12)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadFileRepresentation(forTypeIdentifier: "public.file-url") { url, error in
                if let url = url {
                    DispatchQueue.main.async {
                        store.add(url: url)
                    }
                }
            }
        }
        return true
    }

    private func liquidGlassBackground() -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.1),
                        Color.white.opacity(0.05)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

// MARK: - File Item View

struct FileShelfItemView: View {
    let file: ShelfFile
    let store: FileShelfStore

    @State private var showContextMenu = false
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))

                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 60)
            .onAppear {
                loadIcon()
            }

            Text(file.name)
                .font(.caption2)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: 76)
                .multilineTextAlignment(.center)
        }
        .frame(width: 80)
        .contentShape(Rectangle())
        .onTapGesture {
            store.launchInFinder(id: file.id)
        }
        .onLongPressGesture {
            store.airdrop(id: file.id)
        }
        .contextMenu {
            Button("Open in Finder") {
                store.launchInFinder(id: file.id)
            }

            Button("AirDrop") {
                store.airdrop(id: file.id)
            }

            Divider()

            Button("Remove", role: .destructive) {
                store.remove(id: file.id)
            }
        }
    }

    private func loadIcon() {
        DispatchQueue.global(qos: .userInitiated).async {
            let icon = NSWorkspace.shared.icon(forFile: file.url.path)
            DispatchQueue.main.async {
                self.image = icon
            }
        }
    }
}

#Preview {
    FileShelfView()
}
