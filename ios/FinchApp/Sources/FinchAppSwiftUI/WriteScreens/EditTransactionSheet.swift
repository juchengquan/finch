import SwiftUI
import PhotosUI
import CryptoKit
import QuickLook
import UniformTypeIdentifiers
import FinchCore

/// Edit Transaction (port of the web edit-transaction-form). Editable: merchant,
/// note, date/time, amount, category, tags, receipt attachments, and splitting
/// across categories (a split tx hides amount/category since its legs own them).
/// (Account change is supported by the engine but not surfaced here.) Also
/// exposes confirm / toggle-reviewed / delete. All writes go through
/// FinchStore.apply.
struct EditTransactionSheet: View {
    @EnvironmentObject private var store: FinchStore
    @State private var pendingAttachmentDelete: AttachmentRow?   // receipt awaiting delete confirmation
    @Environment(\.dismiss) private var dismiss

    let txn: Tx

    enum EditKind: String, CaseIterable, Identifiable {
        case expense, income, refund
        var id: String { rawValue }
        var label: String { KindLabel.label(rawValue) }
    }

    @State private var merchant: String
    @State private var note: String
    @State private var date: Date
    @State private var categoryId: String
    @State private var amountText: String
    @State private var selectedTags: Set<String>
    @State private var errorMessage: String?
    @State private var confirmingDelete = false
    @State private var attachments: [AttachmentRow] = []
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var previewURL: URL?
    @State private var status: Entries.Status
    @State private var accountId: String
    /// How this purchase was PAID — one row per card. Seeded from the entry's own
    /// account legs, so opening a split-tender purchase shows what it actually is
    /// rather than the single posting that happened to be tapped.
    ///
    /// Without this the sheet bound a single-select picker to one leg and sent
    /// `patch["account"]`, which the engine refuses on a multi-account entry: the
    /// engine accepted multi-account edits and nothing sent them.
    @State private var accountAlloc = SplitAllocation(total: 0)
    @State private var refundedTxId: String?
    @State private var showingRefundPicker = false
    @State private var currencyCode: String
    @State private var selectedKind: EditKind
    @State private var fromAmountText = ""   // transfer editor: from-leg native amount
    @State private var toAmountText = ""     // transfer editor: to-leg native amount (cross-currency)

    /// The original native (account-currency) amount, the basis for the edit.
    private var originalNative: Double { txn.nativeAmount ?? txn.amount }
    /// A split transaction owns its categories via legs — hide amount/category here.
    /// `txn` re-read from the LIVE store projection (not the init-time snapshot), so a
    /// split written elsewhere reflects here instead of leaving the sheet on the stale
    /// single-category view. (Splits made in THIS sheet are staged, not written, until
    /// save — see `splitAlloc`.)
    private var liveTxn: Tx { store.txns.first(where: { $0.id == txn.id }) ?? txn }
    /// The staged split. Written by `save()` alongside every other field — never on
    /// the picker's Confirm — so cancelling the sheet leaves the ledger untouched.
    @State private var splitAlloc: SplitAllocation
    /// Deliberately the STORED state, not the staged one: this drives the form's
    /// shape — a split layout has no Amount field — and flipping it mid-edit would
    /// remove the very field whose value the split divides.
    private var isSplit: Bool { (liveTxn.splits?.count ?? 0) >= 2 }
    private var refundedSummary: String {
        guard let id = refundedTxId, let t = store.txns.first(where: { $0.id == id }) else { return "Optional" }
        return t.merchant.isEmpty ? t.date : t.merchant
    }
    private var accountCurrency: String {
        store.accounts.first { $0.id == accountId }?.currency ?? store.displayCurrency
    }
    private var currencyOptions: [String] {
        var set = Set(store.accounts.compactMap { $0.currency })
        set.formUnion(store.exchangeRates.map { $0.currency })
        set.insert(accountCurrency)
        return set.sorted()
    }

    init(txn: Tx) {
        self.txn = txn
        _merchant = State(initialValue: txn.merchant)
        _note = State(initialValue: txn.note ?? "")
        _date = State(initialValue: Self.parse(txn.date, txn.time) ?? Date())
        _categoryId = State(initialValue: txn.category ?? "")
        _amountText = State(initialValue: String(format: "%g", abs(txn.nativeAmount ?? txn.amount)))
        _selectedTags = State(initialValue: Set(txn.tags ?? []))
        _status = State(initialValue: txn.pending == true ? .pending : .confirmed)
        _accountId = State(initialValue: txn.account)
        _refundedTxId = State(initialValue: txn.refundedTransactionId)
        _currencyCode = State(initialValue: txn.currency ?? "")
        _selectedKind = State(initialValue: EditKind(rawValue: txn.kind ?? "") ?? (txn.amount > 0 ? .income : .expense))
        // Stored splits arrive PINNED via `merging`, so opening the sheet does not
        // re-divide amounts the user set earlier; repeated categories fold together.
        _splitAlloc = State(initialValue: .merging(
            (txn.splits ?? []).map { (id: $0.categoryId, amount: $0.amount) },
            total: abs(txn.nativeAmount ?? txn.amount)))
    }

    /// Simple single-account entries can be re-typed expense/income/refund.
    private var canReclassify: Bool {
        !isSplit && txn.kind != "transfer" && txn.kind != "adjustment" && txn.kind != "opening"
    }
    private var effectiveKind: String { canReclassify ? selectedKind.rawValue : (txn.kind ?? "expense") }

    private var categories: [CategoryRow] {
        store.pickableCategories.filter { effectiveKind == "income" ? $0.kind == "income" : $0.kind != "income" }
    }

    /// The transfer's two legs — this row plus its counterpart, resolved via
    /// transferGroupId. From = the negative-amount leg.
    private var transferLegs: (from: Tx, to: Tx)? {
        guard txn.kind == "transfer", let gid = txn.transferGroupId else { return nil }
        let legs = store.txns.filter { $0.transferGroupId == gid }
        guard let from = legs.first(where: { $0.amount < 0 }),
              let to = legs.first(where: { $0.amount > 0 }), from.id != to.id else { return nil }
        return (from, to)
    }
    private var transferSameCurrency: Bool {
        guard let legs = transferLegs else { return true }
        return (legs.from.currency ?? "") == (legs.to.currency ?? "")
    }
    private func accountName(_ id: String) -> String {
        store.accounts.first { $0.id == id }?.name ?? "—"
    }
    /// Transfer amount row: fixed currency label from the leg (accounts own
    /// their currency — no picker).
    private func transferAmountRow(_ label: String, text: Binding<String>, currency: String) -> some View {
        FieldRow(glyph: .amount, title: LocalizedStringKey(label), trailing: {
            Text(currency).foregroundStyle(.secondary)
        }) {
            TextField("0.00", text: text).numericInput(text).keyboardType(.decimalPad)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Line items build their own primary section (Account/Amount/
                // Category/Date) below; split & transfer keep Date here.
                if isSplit || transferLegs != nil {
                    Section {
                        FieldRow(glyph: .date, title: "Date", showsDefaultTrailing: false) {
                            DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .environment(\.locale, AppDate.h24Locale)   // 24-hour time wheel regardless of device setting
                        }
                        // Transfers have no Merchant field (design), but previously
                        // exposed Note via this shared top section — keep that.
                        if transferLegs != nil {
                            FieldRow(glyph: .note, title: "Note") {
                                TextField("Note (optional)", text: $note, axis: .vertical)
                            }
                        }
                    }
                }
                if isSplit {
                    // Still the Category row (not a "Split" abstraction) — its value is the
                    // split's category names; tapping it reopens the split editor.
                    Section {
                        // Binds the real category, not a constant: toggling split off in
                        // the subpage hands back the surviving (largest) category, and
                        // save() needs it to name the collapsed transaction.
                        CategoryPickerRow(title: "Category", glyph: .category, categories: categories, selection: $categoryId,
                            noneLabel: String(localized: "Uncategorized"),
                            splitSummary: splitSummaryText(names: splitAlloc.payload.map { store.categoryName($0.id) ?? "Uncategorized" }),
                            splitting: $splitAlloc,
                            currency: txn.currency ?? "")
                            .accessibilityIdentifier("edittx.category")
                    }
                } else if let legs = transferLegs {
                    // Transfer legs: a real transfer editor (spec §2). Accounts are
                    // immutable in updateTransfer → read-only; no Category row for
                    // transfers.
                    Section {
                        FieldRow(glyph: .fromAccount, title: "From") {
                            Text(accountName(legs.from.account))
                        }
                        FieldRow(glyph: .toAccount, title: "To") {
                            Text(accountName(legs.to.account))
                        }
                        // Same currency → one amount row; cross-currency → From + To.
                        if transferSameCurrency {
                            transferAmountRow("Amount", text: $fromAmountText,
                                              currency: legs.from.currency ?? "")
                        } else {
                            transferAmountRow("From amount", text: $fromAmountText,
                                              currency: legs.from.currency ?? "")
                            transferAmountRow("To amount", text: $toAmountText,
                                              currency: legs.to.currency ?? "")
                        }
                    } header: {
                        finchSectionHeader("Transfer")
                    }
                } else {
                    Section {
                        SearchablePickerRow(title: "Account", glyph: .account,
                            accounts: store.accounts, selection: $accountId,
                            splitting: $accountAlloc,
                            currency: currencyCode.isEmpty ? accountCurrency : currencyCode)
                        FieldRow(glyph: .amount, title: "Amount", trailing: {
                            // Currency lives inline with the amount, always visible.
                            Picker("", selection: $currencyCode) {
                                ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu).labelsHidden().fixedSize()
                        }) {
                            TextField("0.00", text: $amountText).keyboardType(.decimalPad).numericInput($amountText)
                        }
                        CategoryPickerRow(title: "Category", glyph: .category, categories: categories, selection: $categoryId,
                            noneLabel: String(localized: "Uncategorized"),
                            splitSummary: splitSummaryText(names: splitAlloc.payload.map { store.categoryName($0.id) ?? "Uncategorized" }),
                            splitting: effectiveKind == "refund" ? nil : $splitAlloc,
                            currency: currencyCode)
                            .accessibilityIdentifier("edittx.category")
                        FieldRow(glyph: .date, title: "Date", showsDefaultTrailing: false) {
                            DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .environment(\.locale, AppDate.h24Locale)
                        }
                        // Refund link inline in the primary section (matches the Add sheet).
                        if effectiveKind == "refund" {
                            Button { showingRefundPicker = true } label: {
                                FieldRow(glyph: .refund, title: "Refunds", isEmpty: refundedTxId == nil) {
                                    Text(refundedSummary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Split still needs an Account row (line items have it above; transfer doesn't).
                if isSplit {
                    Section {
                        SearchablePickerRow(title: "Account", glyph: .account,
                            accounts: store.accounts, selection: $accountId,
                            splitting: $accountAlloc,
                            currency: currencyCode.isEmpty ? accountCurrency : currencyCode)
                    } header: {
                        finchSectionHeader("Account")
                    }
                }
                // Status directly after the primary/split rows (matches the Add sheet).
                Section {
                    // Status keeps its name on the left and the selection on the right.
                    FieldRow(glyph: .status, title: "Status", trailing: {
                        Picker("Status", selection: $status) {
                            Text("Confirmed").tag(Entries.Status.confirmed)
                            Text("Pending").tag(Entries.Status.pending)
                        }
                        .labelsHidden()
                    }) {
                        Text("Status")
                    }
                    // Tags is a single row here (wraps to hold all selected), not its own section.
                    if !store.tags.isEmpty {
                        TagField(tags: store.tags, selected: $selectedTags, glyph: .tags)
                    }
                }

                Section {
                    ForEach(attachments) { att in
                        Button { previewURL = store.attachmentURL(for: att) } label: {
                            HStack {
                                ReceiptThumbnail(url: store.attachmentURL(for: att), kind: att.kind)
                                Text(att.originalFilename ?? att.kind.capitalized).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "eye").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            // Not role: .destructive — fake removal animation pre-confirm.
                            Button { pendingAttachmentDelete = att } label: { Label("Delete", systemImage: "trash") }.tint(.red)
                        }
                        .contextMenu {
                            Button(role: .destructive) { pendingAttachmentDelete = att } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    #if os(macOS)
                    Button { showingFileImporter = true } label: {
                        FieldRow(glyph: .receipt, title: "Add receipt", isEmpty: true) {
                            Text("Add receipt…")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image, .pdf]) { result in
                        if case .success(let url) = result { Task { await addReceiptFile(url) } }
                    }
                    #else
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        FieldRow(glyph: .receipt, title: "Add receipt", isEmpty: pickedPhoto == nil) {
                            Text("Add receipt photo")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    #endif
                } header: {
                    finchSectionHeader("Receipt")
                }

                if txn.kind != "transfer", txn.kind != "adjustment", txn.kind != "opening" {
                    Section {
                        MerchantPickerRow(title: "Merchant", glyph: .merchant,
                                          counterparties: store.counterparties, merchant: $merchant)
                        FieldRow(glyph: .note, title: "Note") {
                            TextField("Note (optional)", text: $note, axis: .vertical)
                        }
                    } header: {
                        finchSectionHeader("Details")
                    }
                }
                // Adjustment/opening entries have no payee, so no Merchant row —
                // but keep an editable Note (e.g. "year-end reconciliation").
                if txn.kind == "adjustment" || txn.kind == "opening" {
                    Section {
                        FieldRow(glyph: .note, title: "Note") {
                            TextField("Note (optional)", text: $note, axis: .vertical)
                        }
                    } header: {
                        finchSectionHeader("Details")
                    }
                }

                // Edit-only meta actions at the very bottom.
                Section {
                    Button(txn.reviewedAt == nil ? "Mark reviewed" : "Unmark reviewed") {
                        run(.setReviewed, ["id": .string(txn.id), "reviewed": .bool(txn.reviewedAt == nil)])
                    }
                    Button("Delete transaction", role: .destructive) { confirmingDelete = true }
                        // Anchored on the button (iOS 26 positions popouts at their source).
                        .confirmationDialog("Delete this transaction?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                do { try store.deleteTransaction(txn.id); Haptics.warning(); dismiss() }   // also unlinks receipt files
                                catch { errorMessage = i18nMessage(error) }
                            }
                        } message: {
                            // This sheet is where "Delete and re-add this purchase to change how
                            // it was paid" (error.tx.splitLegEdit, thrown when editing a split's
                            // amount) sends the user — the worst possible place to then understate
                            // that deleting takes every leg with it. Same wording/precedence as
                            // ActivityTab's delete alert.
                            if txn.transferGroupId != nil {
                                Text(ActivityFeedView.transferDeleteHint)
                            } else if (txn.accountLegCount ?? 1) > 1 {
                                Text(ActivityFeedView.multiLegDeleteHint)
                            }
                        }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Edit Transaction")
            .finchSheetForm()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                // Shared glass type control (TxnTypeToolbar). Line items reclassify
                // across the 3 kinds; a transfer shows a locked single segment;
                // adjustment/opening show none.
                ToolbarItem(placement: .principal) {
                    if canReclassify {
                        TxnTypeToolbar.segmented(EditKind.allCases, selection: $selectedKind,
                            icon: { TxnKindIcon.icon(for: $0.rawValue) }, label: { $0.label })
                    } else if txn.kind == "transfer" {
                        TxnTypeToolbar.locked(icon: TxnKindIcon.icon(for: "transfer"), label: "Transfer")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                        .confirmCheckmarkStyle()
                }
            }
            // Centered ALERT (window-level) — see ActivityTab's delete alert.
            .alert("Delete receipt?", isPresented: Binding(
                get: { pendingAttachmentDelete != nil }, set: { if !$0 { pendingAttachmentDelete = nil } }),
                presenting: pendingAttachmentDelete) { att in
                Button("Delete", role: .destructive) { removeAttachment(att) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The file is deleted permanently.")
            }
            .onChange(of: amountText) { _, newValue in
                // Keep BOTH splits dividing the amount actually on screen.
                //
                // `accountAlloc` was seeded in `.onAppear` and never re-totalled,
                // so typing a new amount changed nothing at all: `save()` sends
                // `payload`, which still held the old per-card figures. You typed
                // 120 over a 100 split, tapped ✓, and 100 was saved in silence.
                //
                // Re-totalling does not by itself move the cells — a reopened
                // split's rows arrive pinned — which is why `save()` also refuses
                // a mismatch rather than trusting this to fix it.
                let total = abs(DecimalInput.parse(newValue) ?? 0)
                splitAlloc.setTotal(total)
                accountAlloc.setTotal(total)
            }
            .quickLookPreview($previewURL)
            .sheet(isPresented: $showingRefundPicker) { RefundSourcePickerView { refundedTxId = $0 } }
            .onAppear {
                attachments = store.attachments(for: txn.id)
                if currencyCode.isEmpty { currencyCode = accountCurrency }
                // Seed the payment split from the entry's OWN legs, so opening a
                // split-tender purchase shows what it actually is rather than the
                // single posting that happened to be tapped. Seeded here rather
                // than in init because `store` is an @EnvironmentObject.
                //
                // Rows arrive PINNED via `merging` — they are amounts the user set
                // before, and must not be re-divided just by opening the sheet.
                let legs = store.txns.filter { $0.entryId != nil && $0.entryId == txn.entryId }
                if legs.count >= 2 {
                    accountAlloc = SplitAllocation.merging(
                        legs.map { (id: Optional($0.account), amount: abs($0.amount)) },
                        total: abs(legs.reduce(0) { $0 + $1.amount }))
                } else {
                    accountAlloc.setTotal(abs(txn.nativeAmount ?? txn.amount))
                }
                if let legs = transferLegs {
                    fromAmountText = String(format: "%g", abs(legs.from.nativeAmount ?? legs.from.amount))
                    toAmountText = String(format: "%g", abs(legs.to.nativeAmount ?? legs.to.amount))
                }
            }
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task { await addReceipt(item) }
            }
        }
    }

    private func addReceipt(_ item: PhotosPickerItem) async {
        errorMessage = nil
        do {
            try await AttachmentWriter.write(item: item, entryId: txn.id, store: store)
            attachments = store.attachments(for: txn.id)
            pickedPhoto = nil
        } catch { errorMessage = i18nMessage(error) }
    }

    private func addReceiptFile(_ url: URL) async {
        errorMessage = nil
        do {
            try await AttachmentWriter.writeFile(url: url, entryId: txn.id, store: store)
            attachments = store.attachments(for: txn.id)
        } catch { errorMessage = i18nMessage(error) }
    }

    private func removeAttachment(_ att: AttachmentRow) {
        do {
            try store.removeAttachment(id: att.id, relPath: att.relPath)   // also unlinks the file
            attachments = store.attachments(for: txn.id)
        } catch { errorMessage = i18nMessage(error) }
    }

    private func save() {
        if txn.kind == "transfer" { saveTransfer(); return }
        errorMessage = nil
        var patch: [String: JSONValue] = [
            "merchant": .string(merchant.isEmpty ? "Untitled" : merchant),
            "note": note.isEmpty ? .null : .string(note),
            "date": .string(Self.day(date)),
            "time": .string(Self.time(date)),
        ]
        let kindChanged = canReclassify && selectedKind.rawValue != txn.kind
        if !isSplit {
            guard let parsed = DecimalInput.parse(amountText), parsed > 0 else {
                errorMessage = "Enter an amount greater than 0."; return
            }
            // Sign by the (possibly new) kind: expense negative; income/refund positive.
            let sign: Double = canReclassify ? (selectedKind == .expense ? -1.0 : 1.0) : (originalNative < 0 ? -1.0 : 1.0)
            let signed = sign * parsed
            if abs(signed - originalNative) > 0.001 || kindChanged { patch["amount"] = .double(signed) }
            // Empty means Uncategorized, and must send an explicit null: omitting the
            // key leaves the old category leg in place, so picking Uncategorized would
            // look like it worked and change nothing. The engine reads a null here as
            // "clear it" (Transactions.swift, `strOrNil(patch["category"])`).
            if categoryId != (txn.category ?? "") {
                patch["category"] = categoryId.isEmpty ? .null : .string(categoryId)
            }
        }
        if kindChanged { patch["kind"] = .string(selectedKind.rawValue) }
        if status != (txn.pending == true ? .pending : .confirmed) { patch["status"] = .string(status.rawValue) }
        if txn.kind != "transfer", !accountId.isEmpty, accountId != txn.account { patch["account"] = .string(accountId) }
        if txn.kind != "transfer", !currencyCode.isEmpty, currencyCode != (txn.currency ?? accountCurrency) {
            patch["currency"] = .string(currencyCode)
        }
        // Refund link: set/update when (now) a refund; clear when leaving refund.
        if effectiveKind == "refund" {
            if refundedTxId != txn.refundedTransactionId || kindChanged {
                patch["refundedTransactionId"] = refundedTxId.map(JSONValue.string) ?? .null
            }
        } else if txn.kind == "refund" {
            patch["refundedTransactionId"] = .null
        }
        // ONE write, replacing the four this path used to fire — five when
        // collapsing a split (createCounterparty, updateTransaction,
        // setTransactionSplits, updateTransaction again, setTransactionTags).
        // Their ORDER was load-bearing and commented as such, which is the tell:
        // a failure between any two left the ledger half-updated.
        //
        // The cells ARE the purchase, so there is no ordering left to get wrong:
        // the amount, the categories and the tags land together or not at all.
        // The amount on screen is the target, and the cells must reach it.
        //
        // A reopened split's rows are pinned, so raising the amount leaves them
        // behind: without this the sheet would post the old figures under the new
        // total and report success. Refused rather than silently reconciled — the
        // user is the only one who knows which cell was wrong.
        if accountAlloc.payload.count >= 2, accountAlloc.problem != nil {
            errorMessage = String(localized: "Splits must add up to the transaction total.")
            return
        }
        if isSplit, splitAlloc.problem != nil {
            errorMessage = String(localized: "Splits must add up to the transaction total.")
            return
        }
        let parsedAmount: Double
        if accountAlloc.payload.count >= 2 {
            parsedAmount = abs(accountAlloc.total)
        } else if isSplit {
            parsedAmount = abs(splitAlloc.total)
        } else {
            guard let parsed = DecimalInput.parse(amountText), parsed > 0 else {
                errorMessage = "Enter an amount greater than 0."; return
            }
            parsedAmount = parsed
        }
        let effKind = canReclassify ? selectedKind.rawValue : (txn.kind ?? "expense")
        let sign: Double = effKind == "expense" ? -1 : 1
        let targetAccount = accountId.isEmpty ? txn.account : accountId
        var cells: [JSONValue] = []
        if accountAlloc.payload.count >= 2 {
            // Paid from several cards. One category across them, because a single
            // transaction is split on at most one axis — both axes is the grid,
            // which is several transactions and reopens through the Add flow.
            let cat: JSONValue = categoryId.isEmpty ? .null : .string(categoryId)
            for share in accountAlloc.payload {
                cells.append(.object([
                    "accountId": .string(share.id ?? targetAccount),
                    "categoryId": cat,
                    "amount": .double(sign * abs(share.amount)),
                ]))
            }
        } else if splitAlloc.payload.count >= 2 {
            for share in splitAlloc.payload {
                cells.append(.object([
                    "accountId": .string(targetAccount),
                    "categoryId": share.id.map(JSONValue.string) ?? .null,
                    "amount": .double(sign * abs(share.amount)),
                ]))
            }
        } else {
            cells.append(.object([
                "accountId": .string(targetAccount),
                "categoryId": categoryId.isEmpty ? .null : .string(categoryId),
                "amount": .double(sign * parsedAmount),
            ]))
        }

        var args: [String: JSONValue] = [
            "id": .string(txn.id),
            "ledgerId": .string(store.activeLedgerId),
            "merchant": .string(merchant.isEmpty ? "Untitled" : merchant),
            "date": .string(Self.day(date)), "time": .string(Self.time(date)),
            "kind": .string(effKind),
            "status": .string(status.rawValue),
            "currency": .string(currencyCode.isEmpty ? (txn.currency ?? accountCurrency) : currencyCode),
            "cells": .array(cells),
            // A set-replace, so clearing every tag actually clears them. The old
            // path only wrote tags when they had changed, which meant the sheet
            // and the engine each had to remember what "unchanged" meant.
            "tagIds": .array(selectedTags.sorted().map { .string($0) }),
        ]
        if !note.isEmpty { args["note"] = .string(note) }
        if effectiveKind == "refund", let refundedTxId { args["refundedTransactionId"] = .string(refundedTxId) }

        do {
            // The merchant is resolve-or-created in the same write, so the separate
            // createCounterparty call is gone — and with it the orphan counterparty
            // a failed save used to leave behind.
            try store.apply(.saveTransaction, Args(args))
            Haptics.success()
            dismiss()
        } catch { Haptics.warning(); errorMessage = i18nMessage(error) }
    }

    /// A transfer saves through the same one write every other kind uses.
    ///
    /// This used to fire up to three commands — `updateTransfer` for the money,
    /// `updateTransaction` for the status, `setTransactionTags` for the tags — so
    /// a failure partway left the transfer changed but its status or tags stale.
    /// One command replaces the transfer's contents wholesale.
    ///
    /// The two amounts are each in their OWN card's currency: there is no single
    /// purchase currency when 110 USD leaves one card and 100 EUR arrives at
    /// another, and the user types both. No `currency` is sent, so the engine
    /// takes each as given.
    ///
    /// The accounts stay read-only here, as they were — changing which cards a
    /// transfer moves between is not something this sheet offers.
    private func saveTransfer() {
        errorMessage = nil
        guard let legs = transferLegs else { errorMessage = "Transfer legs not found."; return }
        guard let from = DecimalInput.parse(fromAmountText), from > 0 else {
            errorMessage = "Enter an amount greater than 0."; return
        }
        var to = from
        if !transferSameCurrency {
            guard let typed = DecimalInput.parse(toAmountText), typed > 0 else {
                errorMessage = "Enter an amount greater than 0."; return
            }
            to = typed
        }
        do {
            var args: [String: JSONValue] = [
                "id": .string(txn.id),
                "ledgerId": .string(store.activeLedgerId), "merchant": .string(""),
                "date": .string(Self.day(date)), "time": .string(Self.time(date)),
                "kind": .string("transfer"), "status": .string(status.rawValue),
                "cells": .array([
                    .object(["accountId": .string(legs.from.account), "categoryId": .null,
                             "amount": .double(-from)]),
                    .object(["accountId": .string(legs.to.account), "categoryId": .null,
                             "amount": .double(to)]),
                ]),
                "tagIds": .array(selectedTags.sorted().map { .string($0) }),
            ]
            if !note.isEmpty { args["note"] = .string(note) }
            try store.apply(.saveTransaction, Args(args))
            Haptics.success()
            dismiss()
        } catch { Haptics.warning(); errorMessage = i18nMessage(error) }
    }

    /// Run a lifecycle action then dismiss (these don't re-edit the open form).
    private func run(_ action: ActionName, _ args: [String: JSONValue]) {
        do { try store.apply(action, Args(args)); dismiss() }
        catch { errorMessage = i18nMessage(error) }
    }

    // MARK: date/time helpers
    private static let dayFmt = AppDate.isoDay
    private static let timeFmt = AppDate.isoTime
    private static let dtFmt = AppDate.isoDateTime
    private static func day(_ d: Date) -> String { dayFmt.string(from: d) }
    private static func time(_ d: Date) -> String { timeFmt.string(from: d) }
    private static func parse(_ ymd: String, _ hm: String?) -> Date? {
        dtFmt.date(from: "\(ymd) \(hm ?? "00:00")") ?? dayFmt.date(from: ymd)
    }
}
