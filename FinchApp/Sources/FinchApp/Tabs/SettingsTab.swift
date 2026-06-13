import SwiftUI
import FinchCore

/// Import/export, the active-ledger picker (switching re-projects), DB info,
/// the audit summary, and the iOS-only "Force import" override (D7).
struct SettingsTab: View {
    @EnvironmentObject private var store: FinchStore
    @EnvironmentObject private var gate: BiometricGate

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ImportButton()
                    ExportButton()
                }

                Section("Active Ledger") {
                    Picker("Active ledger", selection: $store.activeLedgerId) {
                        ForEach(store.ledgers) { ledger in
                            Text(ledger.name).tag(ledger.id)
                        }
                    }
                    LabeledContent("Display currency", value: store.displayCurrency)
                    NavigationLink("Manage ledgers") { LedgerManagementView() }
                }

                Section("Database") {
                    LabeledContent("Filename", value: store.dbInfo.filename)
                    LabeledContent("Size", value: store.dbInfo.formattedSize)
                    LabeledContent("Schema version", value: store.dbInfo.schemaVersion)
                    LabeledContent("Last imported", value: store.dbInfo.lastImportedAtDisplay)
                    ForEach(store.dbInfo.rowCountsOrdered, id: \.0) { name, count in
                        LabeledContent(name, value: "\(count)")
                    }
                }

                Section {
                    Picker("App lock", selection: Binding(
                        get: { gate.settings.policy },
                        set: { gate.settings.policy = $0 })) {
                        ForEach(BiometricPolicy.allCases, id: \.rawValue) { Text($0.displayName).tag($0) }
                    }
                    if gate.settings.policy == .onBackground || gate.settings.policy == .onIdle {
                        Picker("Lock after", selection: Binding(
                            get: { gate.settings.timeoutSeconds },
                            set: { gate.settings.timeoutSeconds = $0 })) {
                            ForEach([60, 300, 900, 1800, 3600], id: \.self) { Text("\($0 / 60) min").tag($0) }
                        }
                    }
                    if gate.settings.policy != .off {
                        Toggle("Require Face ID for export & destructive actions", isOn: Binding(
                            get: { gate.settings.sensitiveActionsEnabled },
                            set: { gate.settings.sensitiveActionsEnabled = $0 }))
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Uses Face ID / Touch ID, falling back to your device passcode. finch never stores a passcode of its own.")
                }

                Section("Notifications") {
                    ForEach(NotificationKind.allCases, id: \.rawValue) { kind in
                        Toggle(kind.title, isOn: Binding(
                            get: { NotificationPrefs.isOn(kind) },
                            set: { on in
                                NotificationPrefs.set(kind, on: on)
                                Task { await NotificationService.shared.refresh() }
                            }))
                    }
                }

                Section("Audit") {
                    if store.auditProblems.isEmpty {
                        Label("Clean", systemImage: "checkmark.seal")
                    } else {
                        NavigationLink {
                            AuditDetailView(problems: store.auditProblems)
                        } label: {
                            Label("\(store.auditProblems.count) problems",
                                  systemImage: "exclamationmark.triangle")
                        }
                    }
                }

                Section {
                    DisclosureGroup("Advanced") {
                        // "Force import" — a DELIBERATE iOS-ONLY DIVERGENCE (D7).
                        // The web has NO audit-skip path; only the native app
                        // offers this override. It re-projects WITHOUT gating on
                        // the audit (the rejected pack's staged DB is swapped in).
                        Button("Force import (skip audit — iOS only)") {
                            store.forceImportCurrentPack()
                        }
                    }
                }

                Section("About") {
                    LabeledContent("App version", value: FinchCore.version)
                    LabeledContent("Pack format", value: FinchCore.packFormatVersion)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

/// The audit-problem list (reached from Settings › Audit when not clean, or
/// after a Force import surfaces the overridden problems).
struct AuditDetailView: View {
    let problems: [Audit.AuditProblem]
    var body: some View {
        List(problems, id: \.self) { problem in
            VStack(alignment: .leading, spacing: 2) {
                Text(problem.code.rawValue).font(.headline)
                if let entryId = problem.entryId {
                    Text("entry: \(entryId)").font(.caption).foregroundStyle(.secondary)
                }
                Text(problem.detail).font(.callout)
            }
        }
        .navigationTitle("Audit problems")
    }
}
