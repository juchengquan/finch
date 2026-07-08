import SwiftUI
import FinchCore

/// FinchStore.buildPack → a temp `.finch` → ShareLink. Disabled until a pack is
/// loaded (no ledgers).
struct ExportButton: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var gate: BiometricGate
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
        // Phase 6.3: a pack contains all financial data — gate behind Face ID
        // when the user enabled sensitive-action protection.
        guard await gate.confirmSensitive() else { return }
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

/// Active-ledger transactions CSV (all months) → temp file → ShareLink. Face-ID
/// gated like the pack — it carries the same transaction data. (The month-scoped
/// variant lives on Insights › Breakdown.)
struct ExportCsvButton: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var gate: BiometricGate
    @State private var exportedFile: ExportedFile?
    @State private var exportError: ImportError?

    var body: some View {
        Button {
            Task { await export() }
        } label: {
            Label("Export transactions (.csv)", systemImage: "tablecells")
        }
        .disabled(store.ledgers.isEmpty)
        .sheet(item: $exportedFile) { file in
            ShareLink(item: file.url, preview: SharePreview("Transactions CSV"))
        }
        .alert(item: $exportError) { err in
            Alert(title: Text("Export failed"), message: Text(err.message),
                  dismissButton: .default(Text("OK")))
        }
    }

    private func export() async {
        guard await gate.confirmSensitive() else { return }
        do {
            let csv = try store.transactionsCsv(month: nil)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("finch-transactions-\(store.activeLedgerId).csv")
            try Data(csv.utf8).write(to: url)
            exportedFile = ExportedFile(url: url)
        } catch {
            exportError = ImportError(message: String(describing: error))
        }
    }
}

/// Drives the menu-bar Export command: watches `router.exportRequested`, builds a
/// pack, and presents a ShareLink — the `ExportButton` flow, hoisted to the shell.
struct ExportCoordinator: ViewModifier {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var gate: BiometricGate
    @ObservedObject private var router = DeepLinkRouter.shared
    @State private var exportedFile: ExportedFile?
    @State private var exportError: ImportError?

    func body(content: Content) -> some View {
        content
            .onChange(of: router.exportRequested) { _, want in
                guard want else { return }
                router.exportRequested = false
                Task { await run() }
            }
            .sheet(item: $exportedFile) { file in
                ShareLink(item: file.url, preview: SharePreview("finch pack"))
            }
            .alert(item: $exportError) { err in
                Alert(title: Text("Export failed"), message: Text(err.message), dismissButton: .default(Text("OK")))
            }
    }

    private func run() async {
        guard await gate.confirmSensitive() else { return }
        do {
            let data = try await store.buildPack()
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("finch-\(UUID().uuidString).finch")
            try data.write(to: tmp)
            exportedFile = ExportedFile(url: tmp)
        } catch { exportError = ImportError(message: String(describing: error)) }
    }
}
