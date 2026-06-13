import Foundation

/// The 74-action write chokepoint catalogue — a verbatim mirror of the web's
/// `lib/db/domain/_args.ts` action keys (the wire contract). Raw values are the
/// camelCase action names sent to `/api/mutate`.
///
/// NOTE: the web has exactly 74 actions today. `setEntryAttachment` (the "75th"
/// the design mentions) does NOT exist in `_args.ts` yet — it lands in Phase 6.5
/// with its handler — so it is intentionally omitted here to keep this enum a
/// faithful 1:1 mirror of the current wire contract (and the 74 parity fixtures).
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
    case confirmTransaction
    case confirmPendingWithMerchant
    case setTransactionTags
    case setTransactionSplits
    case adjustAccountBalance
    case confirmAllPending

    // --- counterparties (5) ---
    case createCounterparty
    case updateCounterparty
    case deleteCounterparty
    case verifyCounterparty
    case unverifyCounterparty

    // --- accounts (5) ---
    case createAccount
    case updateAccount
    case archiveAccount
    case unarchiveAccount
    case deleteAccount

    // --- account groups (3) ---
    case createAccountGroup
    case updateAccountGroup
    case deleteAccountGroup

    // --- budgets (6) ---
    case createBudget
    case updateBudget
    case updateBudgetCycle
    case clearPendingAmount
    case removeBudget
    case contributeBudget

    // --- budget groups (3) ---
    case createBudgetGroup
    case updateBudgetGroup
    case deleteBudgetGroup

    // --- categories (3) ---
    case createCategory
    case updateCategory
    case deleteCategory

    // --- tags (3) ---
    case createTag
    case updateTag
    case deleteTag

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

    // --- app_state (5) ---
    case setMobileTabIds
    case setDisplayCurrency
    case setBackupFrequency
    case setBackupRetention
    case reset
}
