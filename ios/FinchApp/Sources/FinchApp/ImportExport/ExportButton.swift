import SwiftUI
import FinchCore

/// FinchStore.buildPack → a temp `.finch` → ShareLink. Disabled until a pack is
/// loaded (no ledgers).
struct ExportButton: View {
    @EnvironmentObject private var store: FinchStore
    @State private var exportedFile: ExportedFile?
    @State private var isExporting = false
    @State private var exportError: ImportError?

    var body: some View {
        Button {
            Task { await export() }
        } label: {
            Label("Export .finch", systemImage: "square.and.arrow.up")
        }
        .disabled(store.ledgers.isEmpty || isExporting)
        .sheet(item: $exportedFile) { file in
            ShareLink(item: file.url, preview: SharePreview("finch pack"))
        }
        .alert(item: $exportError) { err in
            Alert(title: Text("Export failed"), message: Text(err.message),
                  dismissButton: .default(Text("OK")))
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let data = try await store.buildPack()
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("finch-\(UUID().uuidString).finch")
            try data.write(to: tmpURL)
            exportedFile = ExportedFile(url: tmpURL)
        } catch {
            exportError = ImportError(message: String(describing: error))
        }
    }
}

struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}
