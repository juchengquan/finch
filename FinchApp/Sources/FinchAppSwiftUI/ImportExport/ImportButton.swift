import SwiftUI
import FinchCore
import UniformTypeIdentifiers

/// System file picker → FinchStore.loadPack. Accepts `.finch` (the custom UTI)
/// and `.zip` (a `.finch` IS a zip; some share sheets re-type it). Surfaces
/// PackError to an alert; an audit failure points at the iOS-only override.
struct ImportButton: View {
    @EnvironmentObject private var store: FinchStore
    @State private var isPresentingFilePicker = false
    @State private var importError: ImportError?

    var body: some View {
        Button {
            isPresentingFilePicker = true
        } label: {
            Label("Import .finch", systemImage: "square.and.arrow.down")
        }
        .fileImporter(
            isPresented: $isPresentingFilePicker,
            allowedContentTypes: [UTType("com.juchengquan.finch") ?? .data, .zip],
            onCompletion: handlePicked
        )
        .alert(item: $importError) { err in
            Alert(title: Text("Import failed"), message: Text(err.message),
                  dismissButton: .default(Text("OK")))
        }
    }

    private func handlePicked(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            // Read the bytes inside the security scope, then do the async import
            // inside a Task with a do/catch that surfaces PackError to the alert.
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                importError = ImportError(message: "Could not read the file."); return
            }
            Task { @MainActor in
                do { try await store.loadPack(from: data) }
                catch PackError.auditFailed(let problems) {
                    importError = ImportError(
                        message: "\(problems.count) audit problem(s). Use Settings › About › Force import to override (iOS only).")
                } catch let e as PackError {
                    importError = ImportError(message: String(describing: e))
                } catch {
                    importError = ImportError(message: error.localizedDescription)
                }
            }
        case .failure(let error):
            importError = ImportError(message: error.localizedDescription)
        }
    }
}

struct ImportError: Identifiable {
    let id = UUID()
    let message: String
}
