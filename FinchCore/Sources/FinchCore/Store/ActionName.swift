import Foundation

/// The write chokepoint catalogue — the web's 73 `lib/db/domain/_args.ts` action
/// keys (the wire contract; `contributeBudget` was removed — goal progress is
/// transaction-derived) PLUS Phase 6.5's native-only `setEntryAttachment`. Raw
/// values are the camelCase action names sent to `/api/mutate`.
///
/// `setEntryAttachment` has no web counterpart — the web adds attachments via the
/// multipart `POST /api/attachments` route, not a `mutate` action. The native app
/// has no HTTP server, so it dispatches this local chokepoint write instead. It
/// is NOT part of the web-parity fixtures.
public enum ActionName: String, Codable, Sendable, CaseIterable {
    // --- transactions (15) ---
    case addTransaction
    case updateTransaction
    case setCleared
    case setReviewed
    case markAllReviewed
    case reconcileAccount
    case bulkRecategorize
    case deleteTransaction
    case removeAttachment
    case setEntryAttachment   // Phase 6.5 — the 75th action (native-only; the web uses POST /api/attachments)
    case confirmTransaction
    case confirmPendingWithMerchant
    case setTransactionTags
    case setTransactionSplits
    case adjustAccountBalance
    case confirmAllPending

    // --- counterparties (7) ---
    case createCounterparty
    case updateCounterparty
    case deleteCounterparty
    case verifyCounterparty
    case unverifyCounterparty
    case mergeCounterparty
    case mergeCounterparties

    // --- accounts (6) ---
    case createAccount
    case updateAccount
    case archiveAccount
    case unarchiveAccount
    case deleteAccount
    case setOpeningBalance    // native-first (rewrites the open-<id> entry; the web has no post-creation edit path)

    // --- account groups (3) ---
    case createAccountGroup
    case updateAccountGroup
    case deleteAccountGroup

    // --- budgets (5) ---
    case createBudget
    case updateBudget
    case updateBudgetCycle
    case clearPendingAmount
    case removeBudget

    // --- budget groups (3) ---
    case createBudgetGroup
    case updateBudgetGroup
    case deleteBudgetGroup

    // --- categories (6) ---
    case createCategory
    case updateCategory
    case deleteCategory
    case mergeCategory
    case mergeCategories
    case copyCategories   // native-first — no web parity (Ledger reference copy)
    case setCategoryOrder // native-first — one write for a whole drag (the web has no category reorder)

    // --- tags (6) ---
    case createTag
    case updateTag
    case deleteTag
    case mergeTag     // iOS-only — no web parity (native-ahead)
    case mergeTags    // iOS-only — no web parity (native-ahead)
    case copyTags     // native-first — no web parity (Ledger reference copy)

    // --- rules (4) ---
    case createRule
    case updateRule
    case deleteRule
    case backfillRule

    // --- scheduled (8) ---
    case createScheduled
    case updateScheduled
    case deleteScheduled
    case addScheduledSplit
    case removeScheduledSplit
    case updateScheduledSplit
    case postScheduled
    case generateDueScheduled

    // --- transfers (3) ---
    case createTransfer
    case updateTransfer
    case deleteTransfer

    // --- holdings (4) ---
    case createHolding
    case updateHolding
    case setHoldingPrice
    case deleteHolding

    // --- ledgers (5) ---
    case createLedger
    case updateLedger
    case setDefaultLedger
    case deleteLedger
    case changeLedgerBase

    // --- system (2) ---
    case setExchangeRate
    case deleteExchangeRate

    // --- app_state (7) ---
    case setMobileTabIds
    case setDisplayCurrency
    case setBudgetOrder       // native-first (per-ledger manual budget order; the web ignores the key until it adopts it)
    case setTrackedCurrencies // native-first (global FX auto-update fetch list; the web ignores the key until it adopts it)
    case setBackupFrequency
    case setBackupRetention
    case reset
}
