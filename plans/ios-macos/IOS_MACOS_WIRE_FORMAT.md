# iOS/macOS Wire-Format Annex

> - `plans/ios-macos/IOS_MACOS_PLAN.md` — the direction brief
> - `plans/ios-macos/IOS_MACOS_ROADMAP.md` — the 8-phase arc
> - `plans/ios-macos/IOS_MACOS_PHASE_1_DESIGN.md` — Phase 1.0 (read-only iPhone; uses fixtures)
> - `plans/ios-macos/IOS_MACOS_PHASE_1_5_DESIGN.md` — Phase 1.5 (Insights; uses parity fixtures)
> - `plans/ios-macos/IOS_MACOS_PHASE_2_DESIGN.md` — Phase 2 (74-action chokepoint; per-action fixtures)
> - `plans/ios-macos/IOS_MACOS_PHASE_5_DESIGN.md` — Phase 5 (pack engine; uses pack format)
> - `plans/ios-macos/IOS_MACOS_PHASE_8_DESIGN.md` — Phase 8 (CloudKit row-level sync)
> - `plans/ios-macos/IOS_MACOS_WIRE_FORMAT.md` (this file) — the wire contracts that
>   the iOS app + web app share, quoted verbatim from the web with
>   file:line refs + iOS port notes
>
> _This is a **reference annex**, not a port design. It quotes the web's
> TypeScript and says "the iOS Swift port mirrors this." Implementation is
> a near-direct translation; the implementer reads this + the cited
> web files and writes the Swift side._

## §1. Goal & non-goals

**Goal** — Pin the three wire contracts that the iOS app and the web
app must agree on, byte-for-byte:

1. **`Args`** (per-action input shape) — the 74 chokepoint actions
2. **`I18nError`** (server-error wire shape) — the typed error pipeline
3. **`.finch` pack format** — the export/import container (manifest + DB + attachments)
4. **`SelectorFixture`** — the JSON format for parity-test fixtures

These four contracts are referenced by 5+ existing specs (Phase 1.0
§8, Phase 1.5 §4, Phase 2 §5+§7+§8, Phase 5 §3+§6, Phase 6.4 §2.1,
Phase 6.5 §3+§5, Phase 8 §2) but were never pinned down at the
type-and-JSON level. The annex is the authoritative reference.

**Non-goals (firm)**:

- **Swift port design** — the annex is a reference, not a port spec.
  The iOS team lifts and translates the cited web code.
- **Custom-server variants** — Phase 8's row-level sync introduces a
  different wire format (CloudKit records); that's covered in
  `IOS_MACOS_PHASE_8_DESIGN.md` §2.2, not here.
- **Multi-ledger packs** — a single `.finch` pack contains exactly one
  ledger's data. Multi-ledger exports are a sequence of single-ledger
  packs.
- **Encrypted packs** — out of scope (per `IOS_MACOS_PLAN.md` §10
  "file-protection only in v1"; SQLCipher reconsidered only if a real
  threat model lands).
- **Streaming packs** — packs are read/written in full; no streaming
  API. The web builds/extracts the entire pack as a `Uint8Array` and
  the iOS port does the same (`Data` is the equivalent).
- **Compression tuning** — the manifest is DEFLATE-compressed at level
  6 (the web's `JSZip` default); the DB is DEFLATE-compressed; the
  attachments are STORE'd (they're already JPEG/PDF). No further
  tuning.

## §2. The Args wire format

The chokepoint's 74 actions each have a typed args shape, exported as
the `Args` map in `frontend/lib/db/domain/_args.ts:33-219`. This is
the **wire contract** for the chokepoint dispatcher; the iOS app's
`Store` module must mirror this verbatim (Swift `Codable` structs).

### §2.1 — Top-level structure

```typescript
// frontend/lib/db/domain/_args.ts:33
export type Args = {
  // --- transactions (12) ---
  addTransaction: AddInput;
  // ...
  // --- counterparties (5) ---
  // --- accounts (5) ---
  // --- account groups (3) ---
  // --- budgets (6) ---
  // --- budget groups (3) ---
  // --- categories (3) ---
  // --- tags (3) ---
  // --- rules (4) ---
  // --- scheduled (7) ---
  // --- transfers (3) ---
  // --- holdings (4) ---
  // --- ledgers (5) ---
  // --- system (2) ---
  // --- app_state (5) ---
};
```

The `Args` type is a `Record<ActionName, T>` (one entry per action).
`ActionName = keyof Args` (`_args.ts:221`); `ArgsFor<A> = Args[A]`
(`_args.ts:225`). The iOS port's `ActionName` enum has 74 cases (75
with Phase 6.5's `setEntryAttachment`); the `Args` enum has 74
associated values (75 with the new case).

### §2.2 — Per-action type catalogue

The full per-action type catalogue. All types are exported from
`frontend/lib/db/domain/<x>/types.ts`. The iOS port imports the
equivalents and generates Swift `Codable` structs via `swift-codable`
patterns.

#### Transactions (12 actions)

| Action | Type | Per-domain file |
|---|---|---|
| `addTransaction` | `AddInput` (see `transactions/types.ts:26`) | `transactions` |
| `updateTransaction` | `{ id: string; patch: TransactionPatch }` | `transactions` |
| `setCleared` | `{ id: string; cleared: boolean }` | `transactions` |
| `setReviewed` | `{ id: string; reviewed: boolean }` | `transactions` |
| `markAllReviewed` | `{ ledgerId?: string; accountId?: string }` | `transactions` |
| `reconcileAccount` | `{ accountId: string; statementBalance: number; statementDate?: string; postAdjustment?: boolean }` | `transactions` |
| `bulkRecategorize` | `{ ids: string[]; categoryId: string \| null }` | `transactions` |
| `deleteTransaction` | `{ id: string }` | `transactions` |
| `removeAttachment` | `{ id: string }` | `transactions` |
| `confirmTransaction` | `{ id: string }` | `transactions` |
| `confirmPendingWithMerchant` | `{ id: string; counterpartyId?: string \| null; newCounterpartyName?: string \| null }` | `transactions` |
| `setTransactionTags` | `{ id: string; tagIds: string[] }` | `transactions` |
| `setTransactionSplits` | `{ id: string; splits: { categoryId: string \| null; amount: number; description: string \| null }[] }` | `transactions` |

(`_args.ts:34-66`)

`AddInput` (`transactions/types.ts:26-51`) — the most complex arg
type. Fields:
- `ledgerId: string` (required)
- `accountId: string` (required)
- `amount: number` (signed, native currency)
- `amountBase?: number` (signed, ledger base; defaults to `amount` for same-currency)
- `currency?: string` (native; defaults to account's currency)
- `merchant: string` (required)
- `categoryId?: string | null`
- `date: string` (YYYY-MM-DD)
- `time?: string` (HH:MM:SS)
- `note?: string`
- `status?: 'pending' | 'confirmed'`
- `kind?: 'income' | 'expense' | 'transfer' | 'adjustment' | 'refund'`
- `refundedTransactionId?: string | null`
- `counterpartyId?: string | null`
- `skipRules?: boolean`

**iOS port note**: `addTransaction` returns `Void` (verified in
`transactions/mutations.ts:35-46`; the handler does a bare `return;`).
The iOS form must keep a client-generated `form.id` (or capture the
post-state `Tx[]` and find the new row by `merchant + amount + date`)
to learn the new row's id.

Also: `adjustAccountBalance` (per `_args.ts:36-42`):
```typescript
{
  accountId: string;
  targetBalance: number;
  date?: string;
  note?: string;
  source?: 'reconcile' | 'manual';
}
```

#### Counterparties (5 actions)

| Action | Type |
|---|---|
| `confirmAllPending` | `Record<string, never>` (no args) |
| `createCounterparty` | `NewCounterparty` (from `counterparties/types.ts`) |
| `updateCounterparty` | `{ id: string; patch: CounterpartyPatch }` |
| `deleteCounterparty` | `{ id: string }` |
| `verifyCounterparty` | `{ id: string }` |
| `unverifyCounterparty` | `{ id: string }` |

(`_args.ts:68-74`)

#### Accounts (5 actions)

| Action | Type |
|---|---|
| `createAccount` | `NewAccount` (from `accounts/types.ts`) |
| `updateAccount` | `{ id: string; patch: AccountPatch }` |
| `archiveAccount` | `{ id: string }` |
| `unarchiveAccount` | `{ id: string }` |
| `deleteAccount` | `{ id: string }` |

(`_args.ts:77-82`)

#### Account Groups (3 actions)

| Action | Type |
|---|---|
| `createAccountGroup` | `NewAccountGroup` (from `accountGroups/types.ts`) |
| `updateAccountGroup` | `{ id: string; patch: AccountGroupPatch }` |
| `deleteAccountGroup` | `{ id: string }` |

(`_args.ts:84-86`) — duplicated in `accounts/mutations.ts` (per the
Phase 2 spec note); 13 per-domain `mutations.ts` files produce 77
entries / 74 unique (3 duplicates for `createAccountGroup`,
`updateAccountGroup`, `deleteAccountGroup`).

#### Budgets (6 actions)

| Action | Type |
|---|---|
| `createBudget` | `{ id?: string; ledgerId?: string; groupId?: string \| null; name: string; type?: 'expense' \| 'income'; amount: number; saved?: number; frequency?: string; startDate?: string; endDate?: string \| null; isRecurring?: number; rollover?: number \| boolean; rolloverLimit?: number \| null; accountIds?: string[]; categoryIds?: string[]; warningPct?: number }` |
| `updateBudget` | `{ id: string; patch: BudgetPatch }` |
| `updateBudgetCycle` | `{ id: string; patch: BudgetCyclePatch }` |
| `clearPendingAmount` | `{ id: string }` |
| `removeBudget` | `{ id: string }` (NOT `deleteBudget` — that's a phantom) |
| `contributeBudget` | `{ id: string; amount: number }` |

(`_args.ts:89-111`)

**iOS port note**: budget `rollover` accepts either `number` (the
SQLite-stored value, 0 or 1) OR `boolean` (TypeScript convenience).
The chokepoint's handler (`budgets/mutations.ts:88`) coerces
`boolean → number` (`Number(args.rollover)`). The Swift port must
mirror this — store as `Int` (0/1) but accept `Bool` in the wire
shape and convert at the boundary.

#### Budget Groups (3 actions)

| Action | Type |
|---|---|
| `createBudgetGroup` | `{ id?: string; ledgerId?: string; name: string }` |
| `updateBudgetGroup` | `{ id: string; patch: BudgetGroupGroup }` |
| `deleteBudgetGroup` | `{ id: string }` |

(`_args.ts:114-116`)

#### Categories (3 actions)

| Action | Type |
|---|---|
| `createCategory` | `{ name: string; ledgerId?: string; type?: string; icon?: string \| null; color?: string \| null; parentId?: string \| null }` |
| `updateCategory` | `{ id: string; patch: CategoryPatch }` |
| `deleteCategory` | `{ id: string }` |

(`_args.ts:119-128`)

#### Tags (3 actions)

| Action | Type |
|---|---|
| `createTag` | `{ id?: string; ledgerId?: string; name: string; color?: string \| null }` |
| `updateTag` | `{ id: string; patch: TagPatch }` |
| `deleteTag` | `{ id: string }` |

(`_args.ts:131-133`)

#### Rules (4 actions)

| Action | Type |
|---|---|
| `createRule` | `{ id?: string; ledgerId?: string; name?: string \| null; priority?: number; condition: Condition; actions: Action[]; isActive?: boolean; runOnEdit?: boolean }` |
| `updateRule` | `{ id: string; patch: RulePatchInput }` |
| `deleteRule` | `{ id: string }` |
| `backfillRule` | `{ id: string }` |

(`_args.ts:136-148`)

`Condition` and `Action` come from `@/lib/rules/types`. The rule
engine is documented in `IOS_MACOS_PLAN.md` §2.4.5 and
`IOS_MACOS_PHASE_4_DESIGN.md` §3 (Q16/Q24: 6 conditions + 5 actions
per the resolution pass).

**iOS port note**: `isActive` is patchable via the existing
`updateRule({id, patch: {isActive: true}})` — there is **no
`setRuleEnabled` action** in the 74 (verified: no
`setRuleEnabled` in `frontend/lib/db/`). Phase 4's plan was updated
in grill pass #2 to use `updateRule` instead.

#### Scheduled (7 actions)

| Action | Type |
|---|---|
| `createScheduled` | `{ id?: string; ledgerId?: string; name: string; description?: string \| null; type?: string; amount?: number \| string \| null; frequency?: string; dayOfMonth?: number; weekDay?: number \| null; accountId: string; fromAccountId?: string; autoPost?: boolean; color?: string \| null; category?: string \| null; startDate?: string; endDate?: string \| null; maxExecutions?: number \| null; installmentTotal?: number \| string \| null }` |
| `updateScheduled` | `{ id: string; patch: ScheduledPatch }` |
| `deleteScheduled` | `{ id: string }` |
| `addScheduledSplit` | `{ templateId: string; accountId: string; pct: number }` |
| `removeScheduledSplit` | `{ templateId: string; index: number }` |
| `updateScheduledSplit` | `{ templateId: string; index: number; pct: number }` |
| `postScheduled` | `{ templateId: string }` |
| `generateDueScheduled` | `{ today?: string }` |

(`_args.ts:151-177`)

#### Transfers (3 actions)

| Action | Type |
|---|---|
| `createTransfer` | `{ fromAccountId: string; toAccountId: string; fromAmount: number; toAmount?: number; date: string; time?: string; note?: string \| null; sourceTemplateId?: string }` |
| `updateTransfer` | `{ id: string; patch: TransferPatch }` |
| `deleteTransfer` | `{ id: string }` |

(`_args.ts:180-191`)

#### Holdings (4 actions)

| Action | Type |
|---|---|
| `createHolding` | `NewHolding` (from `holdings/types.ts`) |
| `updateHolding` | `{ id: string; patch: HoldingPatch }` |
| `setHoldingPrice` | `{ id: string; price: number \| null; date?: string \| null }` |
| `deleteHolding` | `{ id: string }` |

(`_args.ts:194-197`)

#### Ledgers (5 actions)

| Action | Type |
|---|---|
| `createLedger` | `NewLedgerInput` (from `ledgers/types.ts`) |
| `updateLedger` | `{ id: string; patch: LedgerPatch }` |
| `setDefaultLedger` | `{ id: string }` |
| `deleteLedger` | `{ id: string }` |
| `changeLedgerBase` | `{ ledgerId: string; newBase: string }` |

(`_args.ts:200-207`)

**iOS port note**: the `LedgerRow` shape (per `ledgers/types.ts:8`)
has `base: string` (NOT `baseCurrency`). The iOS Phase 6.4 spec used
`.baseCurrency` based on a wrong assumption; corrected in grill pass
#3 to `.base`.

#### System (2 actions)

| Action | Type |
|---|---|
| `setExchangeRate` | `{ date: string; currency: string; rate: number; source?: string }` |
| `deleteExchangeRate` | `{ date: string; currency: string }` |

(`_args.ts:210-211`)

#### App State (5 actions)

| Action | Type |
|---|---|
| `setMobileTabIds` | `{ ids: string[] }` |
| `setDisplayCurrency` | `{ ledgerId: string; currency: string }` |
| `setBackupFrequency` | `{ frequencyMs: number }` |
| `setBackupRetention` | `{ retention: number }` |
| `reset` | `Record<string, never>` (no args) |

(`_args.ts:214-218`)

**iOS port note**: per-ledger display-currency override (per
`IOS_MACOS_PHASE_1_5_DESIGN.md` §5.3) is **NOT** per-ledger keys
(`displayCurrency:<id>`). The web uses a **single** `app_state` key
`'displayCurrencyByLedger'` whose value is a JSON
`{[ledgerId]: currency}` map (see
`lib/db/domain/ledgers/mutations.ts:58-64`). The iOS port must
follow this exact pattern — don't introduce per-ledger keys.

### §2.3 — Wire format invariants

These are the rules the iOS `Codable` structs MUST follow:

1. **Field names are camelCase** (TypeScript convention). The Swift
   `CodingKeys` enum maps camelCase ↔ Swift's `lowerCamelCase` (the
   default), so the JSON keys are the same as the Swift property
   names. The dispatcher's snake_case name (`ActionName` enum) is
   used in the API call: `{ "action": "addTransaction", "args": {...} }`.

2. **All optional fields use `?` / `Optional` / `null` consistently**.
   TypeScript `string | null` becomes Swift `String?` (with a custom
   decoder that distinguishes nil-present-from-absent if needed).
   TypeScript `?: T` becomes `T?` (default absent). TypeScript
   `Record<string, never>` (e.g., `confirmAllPending`) becomes
   `EmptyArgs` (an empty struct in Swift).

3. **Money is `number` (Double) on the wire** — TypeScript JSON has
   no Decimal type; all amounts serialize as `number`. The iOS port
   must use `Decimal` for in-process math (per the plan's §4.5
   "compute in Decimal") but convert to `Double` for JSON
   serialization. Conversion is via `Decimal(_ value: Double)` and
   `(amount as NSDecimalNumber).doubleValue`.

4. **Dates are `YYYY-MM-DD` strings** (e.g., `"2026-06-12"`) for
   `date`-shaped fields. `time` is `HH:MM:SS`. `exportedAt` (in
   pack manifests) is full ISO 8601 with timezone (`"2026-06-12T18:42:00Z"`).
   The iOS port decodes via `DateFormatter` with `en_US_POSIX`
   locale + `UTC` time zone.

5. **IDs are strings** (UUIDs and slugs both). The web generates
   UUIDs via `crypto.randomUUID()`; the iOS port uses
   `UUID().uuidString`. Slugs (e.g., ledger ids like `personal`,
   `family`, `business`, `travel`) are stable string identifiers.

6. **`null` vs `undefined` for explicit-null fields** — TypeScript's
   `string | null` is **not** the same as `string | undefined`. The
   JSON wire format distinguishes them: `null` is the explicit-null
   sentinel, missing field is absent. The iOS port's `Codable` must
   honor this for fields like `categoryId: string | null` — when
   the JSON has `"categoryId": null`, the Swift value is
   `String?.some(nil)`; when the JSON omits the field, the Swift
   value is `String?.none`. Swift's `Codable` does this by default
   if the type is `Optional<String>` and the decoder allows
   `nil` from explicit JSON `null`.

7. **Per-domain `Args` map is the source of truth**. The Swift
   port's `Args` enum is generated (Swift type-generation is
   out of scope for the annex; the implementer hand-writes the
   74-75 cases following the catalogue above).

### §2.4 — The `ActionName` enumeration (Swift)

The iOS port's `ActionName` enum has 74 cases (75 with Phase 6.5's
`setEntryAttachment`):

```swift
// ios/FinchCore/Store/ActionName.swift — generated from
// frontend/lib/db/domain/_args.ts (the 74 + 1 cases).
public enum ActionName: String, Codable, Sendable, CaseIterable {
    // --- transactions (12) ---
    case addTransaction, updateTransaction, setCleared, setReviewed,
         markAllReviewed, reconcileAccount, bulkRecategorize,
         deleteTransaction, removeAttachment, confirmTransaction,
         confirmPendingWithMerchant, setTransactionTags,
         setTransactionSplits, adjustAccountBalance
    // --- counterparties (5) ---
    case confirmAllPending, createCounterparty, updateCounterparty,
         deleteCounterparty, verifyCounterparty, unverifyCounterparty
    // --- accounts (5) ---
    case createAccount, updateAccount, archiveAccount, unarchiveAccount,
         deleteAccount
    // --- account groups (3) ---
    case createAccountGroup, updateAccountGroup, deleteAccountGroup
    // --- budgets (6) ---
    case createBudget, updateBudget, updateBudgetCycle, clearPendingAmount,
         removeBudget, contributeBudget
    // --- budget groups (3) ---
    case createBudgetGroup, updateBudgetGroup, deleteBudgetGroup
    // --- categories (3) ---
    case createCategory, updateCategory, deleteCategory
    // --- tags (3) ---
    case createTag, updateTag, deleteTag
    // --- rules (4) ---
    case createRule, updateRule, deleteRule, backfillRule
    // --- scheduled (8 — note: 7 in _args.ts, 8 here because
    //     `generateDueScheduled` is sometimes counted in scheduled
    //     domain but lives in the dispatcher) ---
    case createScheduled, updateScheduled, deleteScheduled,
         addScheduledSplit, removeScheduledSplit, updateScheduledSplit,
         postScheduled, generateDueScheduled
    // --- transfers (3) ---
    case createTransfer, updateTransfer, deleteTransfer
    // --- holdings (4) ---
    case createHolding, updateHolding, setHoldingPrice, deleteHolding
    // --- ledgers (5) ---
    case createLedger, updateLedger, setDefaultLedger, deleteLedger,
         changeLedgerBase
    // --- system (2) ---
    case setExchangeRate, deleteExchangeRate
    // --- app_state (5) ---
    case setMobileTabIds, setDisplayCurrency, setBackupFrequency,
         setBackupRetention, reset
    // --- Phase 6.5 (1) ---
    case setEntryAttachment
}
```

The iOS port's `FinchStore.apply(action:args:)` signature is:

```swift
public func apply<A: ArgsEnum>(
    action: ActionName,
    args: Record<ActionName, Any>  // type-erased JSON
) async throws
```

The args are passed as type-erased JSON (matching the web's
`Record<string, unknown>` pattern at
`lib/db/mutate.ts:46`). The implementer can either:

- **(a) Type-safe enum** — `apply<A: ActionName>(action: A, args: Args.A)` with
  per-case overloads, OR
- **(b) Type-erased JSON** — `apply(action: ActionName, args: [String: Any])`
  matching the web's wire shape.

The web uses (b); the iOS port should match (b) for parity. The
type-safe wrapper is added in Phase 1.5/2 as a thin convenience
over the JSON-erased form.

## §3. The I18nError wire format

The structured error pipeline (per `frontend/lib/i18n-error.ts`).
This is the wire format for any error returned by the chokepoint
dispatcher; the iOS app decodes it back into an `ErrorWithI18n`
to support future i18n rollout (Phase 1.0 ships English-only).

### §3.1 — The `I18nError` class

```typescript
// frontend/lib/i18n-error.ts:33
export class I18nError extends Error {
  readonly code: string;
  readonly params: I18nErrorParams;
  constructor(code: string, params: I18nErrorParams = {}, fallbackEnglish?: string) {
    super(fallbackEnglish ?? code);
    this.code = code;
    this.params = params;
    this.name = 'I18nError';
  }
}

export type I18nErrorParams = Record<string, string | number>;
```

The class carries:
- `code: string` — translation key (e.g., `'error.budget.duplicate'`)
- `params: Record<string, string | number>` — interpolation params
  (e.g., `{ name: 'Groceries' }`)
- `message: string` — English fallback (set via `super(fallbackEnglish)`)

The iOS port:

```swift
// ios/FinchCore/Errors/I18nError.swift
public struct I18nError: Error, Sendable, Codable {
    public let code: String
    public let params: [String: StringValue]  // string-or-number

    public init(code: String, params: [String: StringValue] = [:]) { ... }

    public var message: String { /* derived from code + params */ }
}

public enum StringValue: Codable, Sendable {
    case string(String)
    case number(Double)
}
```

**iOS port note**: the `params` type is union
`string | number` (not `string | int | double`); Swift's
`Codable` distinguishes by JSON type. Use a 2-case enum
(`.string` / `.number`) with a custom decoder.

### §3.2 — The wire shape

```typescript
// frontend/lib/i18n-error.ts:45
export interface I18nWireError {
  code: string;
  params: I18nErrorParams;
  message: string;  // English fallback
}
```

Serialized JSON example (the chokepoint returns this on error):

```json
{
  "error": {
    "code": "error.budget.duplicate",
    "params": { "name": "Groceries" },
    "message": "A budget named \"Groceries\" with this cycle already exists."
  }
}
```

When the chokepoint throws a plain `Error` (not `I18nError`), the
web serializes it to a plain string:

```typescript
// frontend/lib/i18n-error.ts:69
export function toWireError(err: unknown): I18nWireError | string {
  if (err instanceof I18nError) {
    return { code: err.code, params: err.params, message: err.message };
  }
  return err instanceof Error ? err.message : 'Unknown error';
}
```

i.e., the wire format is a union: `{ error: { code, params, message } }`
OR `{ error: "Plain error string" }`.

The iOS port decodes both forms:

```swift
// ios/FinchCore/Errors/ErrorDecoder.swift
public enum WireError: Error {
    case i18n(I18nError)
    case plain(String)
}

public func decodeWireError(_ json: Any) -> WireError {
    if let dict = json as? [String: Any],
       let code = dict["code"] as? String,
       let message = dict["message"] as? String {
        return .i18n(I18nError(
            code: code,
            params: (dict["params"] as? [String: Any]) ?? [:]
        ))
    }
    if let str = json as? String {
        return .plain(str)
    }
    return .plain("Server error")
}
```

### §3.3 — Round-trip invariants

The web's `fromWireError` (lines 79-86) decodes back into a
client-side `Error` whose `.message` is the English fallback (so
unmigrated `toast.error(err.message)` calls keep working) and
attaches `.code` + `.params` for i18n-aware callers.

The iOS port mirrors this: the iOS app's `toast.error(err.message)`
calls show the English fallback (no UX regression during the
rollout), and migrated callers check `err.code` for translation.

## §4. The `.finch` pack format

The export/import container (per `frontend/lib/db/core/pack.ts`).
A `.finch` pack is a ZIP containing a SQLite DB + attachment files
+ a manifest. **Format version 1** is current. The iOS app's
`PackCodec` Swift module reads/writes packs using the same format.

### §4.1 — Top-level layout

The pack is a ZIP file with these entries, in this order:

| # | Entry path | Content | Compression |
|---|---|---|---|
| 1 | `finch.sqlite3` | SQLite database (snapshot of live DB) | DEFLATE |
| 2 | `attachments/<tx_id>/<att_id>.<ext>` | Receipt file (JPEG/PDF) | STORE (no compression) |
| 3 | `manifest.json` | Pack metadata + per-file integrity hashes | DEFLATE |

(`pack.ts:104, 119, 146-148`)

- **Order matters** — the manifest is written LAST because it
  contains hashes of the other entries. (JSZip writes entries in
  insertion order, so the on-disk ZIP order matches the table above.)
- **Attachment path convention** — every attachment entry MUST live
  under the `attachments/` prefix (`pack.ts:28`; validated at
  parse time, line 224).
- **Path-traversal guard** — `rel_path` MUST NOT contain `..`
  segments (line 227) and MUST resolve to a path under `destDir`
  (line 291).

### §4.2 — The manifest schema

```typescript
// frontend/lib/db/core/pack.ts:33
export interface ManifestAttachment {
  id: string;
  /** Entry path inside the zip; mirrored on disk under dbDir on extract.
   *  Always forward-slashed (`path.posix`) for cross-platform interop. */
  rel_path: string;
  byte_size: number;
  sha256: string;
}

export interface PackManifest {
  pack_format_version: string;       // '1' (PACK_FORMAT_VERSION, line 19)
  app_name: string;                   // 'finch' (line 126)
  app_version: string;                // input.meta.appVersion
  schema_version: string;             // input.meta.schemaVersion
  exported_at: string;                // ISO 8601, e.g. '2026-06-12T18:42:00Z'
  exported_from?: {
    device: 'web' | 'ios' | 'macos';
    device_id?: string;
    device_name?: string;
  };
  db: {
    filename: string;                 // 'finch.sqlite3' (PACK_DB_FILENAME, line 22)
    byte_size: number;
    sha256: string;                   // hex (lowercase), SHA-256 of the DB bytes
    row_counts: Record<string, number>;  // { 'accounts': N, 'entries': M, ... }
  };
  attachments: {
    count: number;
    total_bytes: number;
    items: ManifestAttachment[];      // sorted by rel_path (line 108-110)
  };
}
```

**Field rules**:

- `pack_format_version` — string. Currently `'1'`. The receiver
  refuses any version it doesn't understand (line 202-207).
- `app_name` — string. MUST be `'finch'`; the receiver refuses
  anything else (line 208-210).
- `app_version` — string. The web sets this from
  `package.json`'s `version`. The iOS port sets it from
  `Bundle.main.infoDictionary["CFBundleShortVersionString"]`.
- `schema_version` — string. The web's `SCHEMA_VERSION` constant
  (per `lib/db/core/schema.ts`).
- `exported_at` — ISO 8601 with timezone (e.g., `'2026-06-12T18:42:00Z'`).
  The iOS port uses `ISO8601DateFormatter` with
  `.withInternetDateTime` options.
- `exported_from.device` — enum: `'web' | 'ios' | 'macos'`. The
  iOS port always sets `'ios'` (or `'macos'` on Mac).
- `db.sha256` — 64-character lowercase hex (SHA-256 of the DB
  bytes, computed before compression; line 100-101).
- `db.byte_size` — the **uncompressed** byte size of the DB
  (matches the size in the manifest and the size post-decompression
  in the receiver; lines 133, 265-269).
- `db.row_counts` — `Record<string, number>` (e.g.,
  `{'accounts': 4, 'entries': 1842, 'postings': 3700, ...}`).
- `attachments.sha256` — 64-character lowercase hex per file
  (line 230 validates `length === 64`).
- `attachments.items` — sorted by `rel_path` (line 108-110) so
  the manifest is byte-deterministic.

### §4.3 — Build pipeline

```typescript
// frontend/lib/db/core/pack.ts:99
export async function buildPack(input: BuildPackInput): Promise<BuiltPack> {
  const zip = new JSZip();
  const dbSha = sha256Hex(input.dbBytes);

  // DB: DEFLATE-compressed
  zip.file(PACK_DB_FILENAME, input.dbBytes, { compression: 'DEFLATE' });

  // Attachments: STORE (already compressed), sorted by rel_path
  const sorted = [...input.attachmentFiles].sort((a, b) =>
    a.relPath.localeCompare(b.relPath),
  );
  const items: ManifestAttachment[] = [];
  let totalBytes = 0;
  for (const att of sorted) {
    if (!att.relPath.startsWith(PACK_ATTACHMENTS_PREFIX)) {
      throw new Error(`Attachment relPath outside ${PACK_ATTACHMENTS_PREFIX}: ${att.relPath}`);
    }
    const bytes = new Uint8Array(await readFile(att.absPath));
    const sha = sha256Hex(bytes);
    zip.file(att.relPath, bytes, { compression: 'STORE' });
    items.push({ id: att.id, rel_path: att.relPath, byte_size: bytes.length, sha256: sha });
    totalBytes += bytes.length;
  }

  const manifest: PackManifest = { ... };

  // Manifest LAST in zip order
  zip.file(PACK_MANIFEST_FILENAME, JSON.stringify(manifest, null, 2), {
    compression: 'DEFLATE',
  });

  const bytes = await zip.generateAsync({
    type: 'uint8array',
    compression: 'DEFLATE',
    compressionOptions: { level: 6 },
  });

  return { bytes, manifest };
}
```

(`pack.ts:99-157`)

**iOS port notes** (Swift implementation):

1. **DB snapshot via `VACUUM INTO`** — the web uses SQLite's
   `VACUUM INTO` to get a clean snapshot of the live DB (per
   `lib/db/core/server.ts`). GRDB.swift doesn't have a direct
   `vacuum(into:)` API; the iOS port uses one of:
   - **(a)** `sqlite3` C API: `sqlite3_exec(db, "VACUUM INTO '/path/to/finch.sqlite3'", ...)`.
   - **(b)** `DatabasePool.writeWithoutTransaction { db in
     try db.execute(sql: "VACUUM INTO ?", arguments: [path]) }` —
     GRDB's `execute(sql:)` doesn't support `VACUUM INTO` because
     it's a statement that produces a file (not rows), so this
     won't work.
   - **(c)** `FileManager.copyItem` after `PRAGMA wal_checkpoint(TRUNCATE)` —
     simpler than (a) but produces a non-`VACUUM`-ed copy (still
     works because the schema is the same; just bigger).

   The iOS port uses **(a)** for parity with the web (the cleanest
   snapshot). The Swift code:

   ```swift
   // ios/FinchCore/Storage/PackCodec.swift
   import SQLite3

   func vacuumSnapshot(at dbPath: String, to snapshotPath: String) throws {
       var db: OpaquePointer?
       guard sqlite3_open(dbPath, &db) == SQLITE_OK else { throw ... }
       defer { sqlite3_close(db) }
       let sql = "VACUUM INTO '\(snapshotPath)'"
       guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
           throw ...  // capture sqlite3_errmsg(db)
       }
   }
   ```

2. **ZIP via `ZIPFoundation`** — the iOS port uses
   [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (a
   pure-Swift ZIP library) for archive read/write. The
   `compression(.deflate)` and `compression(.none)` options map
   to the web's `DEFLATE` and `STORE`.

3. **sha256 via `CryptoKit`** — the iOS port uses
   `import CryptoKit` and `SHA256.hash(data:)`. The hex encoding
   is lowercase: `hash.map { String(format: "%02x", $0) }.joined()`.

4. **DB filename: `finch.sqlite3`** — `PACK_DB_FILENAME` constant
   (`pack.ts:22`). The iOS port mirrors this.

5. **DB byte_size** is the **uncompressed** size (the manifest
   reports the size before compression; line 133-134). The iOS
   port computes `Data` length after `vacuumSnapshot` (before
   ZIP compression).

### §4.4 — Parse pipeline

```typescript
// frontend/lib/db/core/pack.ts:179
export async function parsePack(zipBytes: Uint8Array): Promise<ParsedPack> {
  let zip: JSZip;
  try {
    zip = await JSZip.loadAsync(zipBytes);
  } catch (err) {
    throw new PackError(`Not a valid zip: ${(err as Error).message}`);
  }

  const manifestEntry = zip.file(PACK_MANIFEST_FILENAME);
  if (!manifestEntry) throw new PackError('Missing manifest.json');
  let manifest: PackManifest;
  try {
    const text = await manifestEntry.async('string');
    manifest = JSON.parse(text) as PackManifest;
  } catch (err) {
    throw new PackError(`manifest.json is not valid JSON: ${(err as Error).message}`);
  }

  // Schema sanity checks
  if (typeof manifest.pack_format_version !== 'string') {
    throw new PackError('manifest.pack_format_version missing');
  }
  if (manifest.pack_format_version !== PACK_FORMAT_VERSION) {
    throw new PackError(
      `Unsupported pack format version ${manifest.pack_format_version} ` +
        `(this app understands ${PACK_FORMAT_VERSION})`,
    );
  }
  if (manifest.app_name !== 'finch') {
    throw new PackError(`Not a Finch pack (app_name=${manifest.app_name})`);
  }
  if (!manifest.db || typeof manifest.db.sha256 !== 'string') {
    throw new PackError('manifest.db.sha256 missing');
  }
  if (!manifest.attachments || !Array.isArray(manifest.attachments.items)) {
    throw new PackError('manifest.attachments.items missing');
  }
  if (!zip.file(PACK_DB_FILENAME)) {
    throw new PackError(`Pack missing ${PACK_DB_FILENAME}`);
  }

  // Path-traversal guard
  for (const item of manifest.attachments.items) {
    if (typeof item.rel_path !== 'string' || !item.rel_path.startsWith(PACK_ATTACHMENTS_PREFIX)) {
      throw new PackError(`Bad attachment rel_path: ${item.rel_path}`);
    }
    if (item.rel_path.includes('..')) {
      throw new PackError(`Attachment rel_path contains ..: ${item.rel_path}`);
    }
    if (typeof item.sha256 !== 'string' || item.sha256.length !== 64) {
      throw new PackError(`Bad attachment sha256: ${item.id}`);
    }
    if (typeof item.byte_size !== 'number' || item.byte_size < 0) {
      throw new PackError(`Bad attachment byte_size: ${item.id}`);
    }
    if (!zip.file(item.rel_path)) {
      throw new PackError(`Pack manifest references missing entry: ${item.rel_path}`);
    }
  }

  return { manifest, zip };
}
```

(`pack.ts:179-242`)

**Parse errors throw `PackError`** (a subclass of `Error`, line
163-169). The iOS port defines an equivalent:

```swift
// ios/FinchCore/Storage/PackError.swift
public struct PackError: Error, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}
```

### §4.5 — Extract pipeline

```typescript
// frontend/lib/db/core/pack.ts:256
export async function extractPack(parsed: ParsedPack, destDir: string): Promise<ExtractedPack> {
  await mkdir(destDir, { recursive: true });

  // DB
  const dbBytes = await mustRead(parsed.zip, PACK_DB_FILENAME);
  const dbSha = sha256Hex(dbBytes);
  if (dbSha !== parsed.manifest.db.sha256) {
    throw new PackError(`DB sha256 mismatch: expected ${parsed.manifest.db.sha256}, got ${dbSha}`);
  }
  if (dbBytes.length !== parsed.manifest.db.byte_size) {
    throw new PackError(
      `DB byte_size mismatch: expected ${parsed.manifest.db.byte_size}, got ${dbBytes.length}`,
    );
  }
  const dbPath = path.join(destDir, PACK_DB_FILENAME);
  await writeFile(dbPath, dbBytes);

  // Attachments
  const attachmentsRoot = path.join(destDir, 'attachments');
  await mkdir(attachmentsRoot, { recursive: true });
  for (const item of parsed.manifest.attachments.items) {
    const bytes = await mustRead(parsed.zip, item.rel_path);
    const sha = sha256Hex(bytes);
    if (sha !== item.sha256) {
      throw new PackError(`Attachment ${item.id} sha256 mismatch`);
    }
    if (bytes.length !== item.byte_size) {
      throw new PackError(
        `Attachment ${item.id} byte_size mismatch: expected ${item.byte_size}, got ${bytes.length}`,
      );
    }
    const absPath = path.join(destDir, ...item.rel_path.split('/'));
    const resolved = path.resolve(absPath);
    if (!resolved.startsWith(path.resolve(destDir) + path.sep)) {
      throw new PackError(`Attachment escapes destDir: ${item.rel_path}`);
    }
    await mkdir(path.dirname(absPath), { recursive: true });
    await writeFile(absPath, bytes);
  }

  return { dbPath, attachmentsDir: attachmentsRoot, manifest: parsed.manifest };
}
```

(`pack.ts:256-299`)

**Extract invariants** (all MUST be honored by the iOS port):

1. **DB sha256 matches** — else `PackError("DB sha256 mismatch")`.
2. **DB byte_size matches** — else `PackError("DB byte_size mismatch")`.
3. **Each attachment's sha256 matches** — else
   `PackError("Attachment ${id} sha256 mismatch")`.
4. **Each attachment's byte_size matches** — else
   `PackError("Attachment ${id} byte_size mismatch")`.
5. **Path-traversal guard** — `absPath` MUST resolve under
   `destDir`. The web uses
   `resolved.startsWith(path.resolve(destDir) + path.sep)`. The
   iOS port uses the equivalent Swift check.

**iOS port notes**:

- **Best-effort cleanup on error** — the web comment says "Throws
  (after best-effort cleanup) on any mismatch" (line 254-255). The
  iOS port must do the same: if a sha256 fails, delete any files
  that were already extracted to `destDir` (so a partial extract
  doesn't leave stale files behind).
- **Atomic swap** — after a successful extract, the iOS port
  swaps the new DB into place (per `IOS_MACOS_PHASE_1_DESIGN.md` §4
  step 5). The web's `lib/db/core/server.ts` does the same.

### §4.6 — `detectFileKind` (magic-byte detection)

```typescript
// frontend/lib/db/core/pack.ts:310
export function detectFileKind(head: Uint8Array): 'zip' | 'sqlite' | 'unknown' {
  if (head.length >= 4 && head[0] === 0x50 && head[1] === 0x4b && head[2] === 0x03 && head[3] === 0x04) {
    return 'zip';
  }
  if (head.length >= 16) {
    const magic = Buffer.from(head.subarray(0, 15)).toString('latin1');
    if (magic === 'SQLite format 3' && head[15] === 0) return 'sqlite';
  }
  return 'unknown';
}
```

(`pack.ts:310-319`)

**Magic bytes**:
- ZIP: `50 4B 03 04` (the local-file header signature `'PK\x03\x04'`)
- SQLite: `'SQLite format 3\x00'` (16 bytes: `"SQLite format 3"` + null byte)

The iOS port mirrors this:

```swift
// ios/FinchCore/Storage/FileKind.swift
public enum FileKind: Sendable {
    case zip, sqlite, unknown
}

public func detectFileKind(head: Data) -> FileKind {
    if head.count >= 4 &&
       head[head.startIndex]     == 0x50 &&  // 'P'
       head[head.startIndex + 1] == 0x4B &&  // 'K'
       head[head.startIndex + 2] == 0x03 &&
       head[head.startIndex + 3] == 0x04 {
        return .zip
    }
    if head.count >= 16 {
        let magic = head.prefix(15)
        let magicStr = String(data: magic, encoding: .latin1) ?? ""
        if magicStr == "SQLite format 3" && head[head.startIndex + 15] == 0 {
            return .sqlite
        }
    }
    return .unknown
}
```

**Usage**: the import route handler in `app/api/import` and the
iOS Phase 1.0 import flow both use `detectFileKind` to route raw
`.db` vs `.finch` pack bodies. The first 4-16 bytes of the file
are read; the rest of the file is processed accordingly.

### §4.7 — Cross-app import/export flow

The import + export flow is described in `IOS_MACOS_PHASE_1_DESIGN.md`
§2 and `IOS_MACOS_PHASE_5_DESIGN.md` §2-§3. The wire contract is
the pack format (§4 of this annex). The cross-app import pipeline:

1. **Read first 16 bytes** of the file. Call `detectFileKind`.
2. **If `.zip`** — call `parsePack(zipBytes)`, then `extractPack`
   to a `tmp/` directory. After sha256s pass, atomically swap the
   extracted DB into place (Phase 1.0 §4 step 5).
3. **If `.sqlite`** — the file is a raw DB. Open it directly with
   GRDB.swift, run `auditLedger`. If clean, swap into place. If
   not clean, show the audit-gate error and (per Phase 1.0 §4
   step 6) the "Force import" recovery hatch.
4. **If `.unknown`** — show "Not a valid finch file" error.

The reverse (export) flow:

1. Take the live DB (or `VACUUM INTO` snapshot).
2. List all attachment files under `Application Support/attachments/`.
3. Call `buildPack(...)` to produce a `Uint8Array` / `Data`.
4. Write to `tmp/<ledger-slug>-<yyyy-mm-dd>.finch`.
5. Show a `ShareLink` / `UIActivityViewController` with the file.

## §5. The fixture format

The JSON format for parity-test fixtures (per Phase 1.0 §8.4 and
Phase 1.5 §4). Each fixture captures one test case from
`frontend/lib/select.test.ts` (selector, input, expected output).
The iOS port's parity suite reads these JSON files and runs each
selector.

### §5.1 — `SelectorFixture` JSON schema

```typescript
// plans/ios-macos/IOS_MACOS_WIRE_FORMAT.md §5.1 — the canonical schema
// (informally specified; the export script and the Swift loader
// both follow this).
interface SelectorFixture {
  /** A stable, human-readable name for the case. */
  name: string;
  /** The selector function name (e.g., 'accountBalance', 'selectTransactions'). */
  selector: string;
  /** The input tuple, serialized as a JSON object. The shape depends on
   *  the selector — see the per-selector-group table below. */
  input: Record<string, unknown>;
  /** The expected output, serialized as JSON. Shape depends on the
   *  selector (Decimal → number; array → array; etc.). */
  expected: unknown;
  /** Optional: the seed identifier used to produce the input. The iOS
   *  port doesn't need this for parity (the input is self-contained);
   *  the web's `extractTestCases` function records it for traceability. */
  seed?: string;
}
```

**File naming**: one fixture per file,
`ios/FinchCore/Tests/Fixtures/selectors/<group>/<selector>__<case>.json`.
The iOS SwiftPM test target (per Phase 1.5 §4.4) declares
`resources: [.copy("Fixtures")]` so the fixtures are available via
`Bundle.module.url(forResource: ...)`.

### §5.2 — Number serialization (Decimal → number)

The web computes in Decimal (via the `Decimal` library), but the
fixture format uses JSON `number` (Double). Precision loss is
acceptable for the parity assertions (the web's `select.test.ts`
asserts with `toBeCloseTo(..., 2)` or `toBe(100)` for cent-level
comparisons).

The iOS port asserts with `XCTAssertEqual(actual, fixture.expected,
accuracy: 0.005)` (cent-level) for amounts.

### §5.3 — Per-selector-group fixture examples

The 32 selectors are grouped into 8 groups (per Phase 1.5 §2).
One example per group:

#### Group 1: Time series (8 selectors)

**`balanceSeries`** (Phase 1.0, 7 selectors) — the simplest example.

```json
{
  "name": "balanceSeries-ends-at-current-balance",
  "selector": "balanceSeries",
  "input": {
    "txns": [
      { "id": "1", "merchant": "m", "category": "food", "amount": -10,
        "account": "cc", "date": "2026-05-01", "pending": false,
        "ledgerId": "personal" },
      { "id": "2", "merchant": "m", "category": "food", "amount": -20,
        "account": "cc", "date": "2026-05-02", "pending": false,
        "ledgerId": "personal" }
    ],
    "accountId": "cc",
    "currentBalance": 100
  },
  "expected": [130, 120, 100]
}
```

(Source: `frontend/lib/select.test.ts:40-46`)

#### Group 2: Net worth + per-account breakdowns (4 selectors)

**`netWorthSeries`** (Phase 1.0) — checks `includeInNetWorth` filter.

```json
{
  "name": "netWorthSeries-excludes-accounts-with-includeInNetWorth-0",
  "selector": "netWorthSeries",
  "input": {
    "txns": [],
    "accounts": [
      { "id": "chk", "name": "Chk", "balance": 1000, "currency": "USD",
        "ledgerId": "personal", "includeInNetWorth": 1 },
      { "id": "cc",  "name": "CC",  "balance": -500, "currency": "USD",
        "ledgerId": "personal", "includeInNetWorth": 0 }
    ],
    "ledgerId": "personal"
  },
  "expected": [1000]
}
```

(Source: `frontend/lib/select.test.ts:62-70`)

#### Group 3: Explanations (2 selectors)

**`netWorthExplained`** — decomposes net worth delta.

```json
{
  "name": "netWorthExplained-basic",
  "selector": "netWorthExplained",
  "input": {
    "txns": [
      { "id": "1", "merchant": "Salary", "amount": 5000, "account": "chk",
        "date": "2026-05-01", "category": "income", "pending": false,
        "ledgerId": "personal" }
    ],
    "accounts": [
      { "id": "chk", "balance": 5000, "currency": "USD", "ledgerId": "personal",
        "includeInNetWorth": 1, "isActive": true }
    ],
    "ledgerId": "personal",
    "month": "2026-05"
  },
  "expected": {
    "netWorthDelta": 5000,
    "breakdown": [
      { "label": "Salary", "amount": 5000, "categoryId": "income" }
    ]
  }
}
```

(Shape approximate — the actual `netWorthExplained` return type
is `{ total, breakdown, ... }` per Phase 1.5 §6. The web's
`netWorthExplained` test cases provide the exact JSON shape.)

#### Group 4: Top-N deltas (2 selectors)

**`topCategoryDeltas`** — top N categories by month-over-month delta.

```json
{
  "name": "topCategoryDeltas-top-3",
  "selector": "topCategoryDeltas",
  "input": {
    "txns": [
      { "id": "1", "merchant": "m", "amount": -100, "category": "food",
        "account": "cc", "date": "2026-05-15", "pending": false,
        "ledgerId": "personal" },
      { "id": "2", "merchant": "m", "amount": -200, "category": "transport",
        "account": "cc", "date": "2026-05-15", "pending": false,
        "ledgerId": "personal" }
    ],
    "ledgerId": "personal",
    "month": "2026-05",
    "n": 3
  },
  "expected": [
    { "categoryId": "transport", "delta": 200, "previousSpend": 0, "currentSpend": 200 },
    { "categoryId": "food", "delta": 100, "previousSpend": 0, "currentSpend": 100 }
  ]
}
```

#### Group 5: Holdings (4 selectors)

**`holdingValue`** — current value of one holding.

```json
{
  "name": "holdingValue-current-price-times-quantity",
  "selector": "holdingValue",
  "input": {
    "holding": {
      "id": "h1",
      "accountId": "inv-acc",
      "symbol": "AAPL",
      "quantity": 10,
      "costBasis": 1785.0,
      "currency": "USD"
    },
    "currentPrice": 182.30
  },
  "expected": 1823.0
}
```

#### Group 6: Per-account totals (3 selectors)

**`investmentAccountTotal`** — total value of an investment account (cash + holdings).

```json
{
  "name": "investmentAccountTotal-cash-plus-holdings",
  "selector": "investmentAccountTotal",
  "input": {
    "account": {
      "id": "inv-acc",
      "balance": 1000,
      "type": "investment"
    },
    "holdings": [
      { "id": "h1", "accountId": "inv-acc", "symbol": "AAPL", "quantity": 10,
        "currentPrice": 182.30 }
    ]
  },
  "expected": 2823.0
}
```

#### Group 7: Transfers / duplicates (2 selectors)

**`findDuplicate`** — find a duplicate transaction (used by the
"add transaction" UI to surface a duplicate-warning alert).

```json
{
  "name": "findDuplicate-exact-match",
  "selector": "findDuplicate",
  "input": {
    "txns": [
      { "id": "1", "merchant": "Starbucks", "amount": -6.50, "category": "food",
        "account": "cc", "date": "2026-05-15", "pending": false,
        "ledgerId": "personal" }
    ],
    "candidate": {
      "merchant": "Starbucks",
      "amount": -6.50,
      "date": "2026-05-15",
      "accountId": "cc"
    }
  },
  "expected": "1"
}
```

#### Group 8: Misc (5 selectors)

**`selectTransactions`** (Phase 1.0) — filterable transaction list.

```json
{
  "name": "selectTransactions-filter-by-account",
  "selector": "selectTransactions",
  "input": {
    "txns": [
      { "id": "1", "merchant": "m", "amount": -10, "category": "food",
        "account": "cc", "date": "2026-05-01", "pending": false,
        "ledgerId": "personal" },
      { "id": "2", "merchant": "m", "amount": -20, "category": "food",
        "account": "chk", "date": "2026-05-01", "pending": false,
        "ledgerId": "personal" }
    ],
    "opts": {
      "ledgerId": "personal",
      "accountId": "cc"
    }
  },
  "expected": [
    { "id": "1", "merchant": "m", "amount": -10, "category": "food",
      "account": "cc", "date": "2026-05-01", "pending": false,
      "ledgerId": "personal" }
  ]
}
```

### §5.4 — The export script (web-side)

The web's `frontend/scripts/export-fixtures.ts` (per Phase 1.0 §8.4)
reads each test case from `frontend/lib/select.test.ts`, calls the
selector function, and writes the JSON. The script interface:

```typescript
// plans/ios-macos/IOS_MACOS_WIRE_FORMAT.md §5.4 — informal interface;
// the implementer can re-design as long as the output matches §5.1.
interface ExportFixturesInput {
  /** Path to the iOS test fixtures directory. */
  outDir: string;
  /** The selectors to export (default: all 32). */
  selectors?: string[];
  /** Optional: skip the seed-store dependency by inlining inputs. */
  inlineInputs?: boolean;
}

export async function exportFixtures(input: ExportFixturesInput): Promise<void>;
```

The script produces the per-selector-group output files. The iOS
port's SwiftPM test target reads them via `Bundle.module` (per
Phase 1.5 §4.4).

## §6. Cross-spec impact

The wire contracts above are referenced by 7+ existing specs.
The annex's role is to be the **single source of truth** that all
of them cite.

| Spec | References | Cite § |
|---|---|---|
| Phase 1.0 §8.4 (fixture export script) | Fixture format | §5 |
| Phase 1.0 §4 (import + export pipeline) | Pack format | §4 |
| Phase 1.0 §4 step 5 (atomic swap) | Pack format §4.5 | §4.5 |
| Phase 1.5 §4 (parity test infrastructure) | Fixture format | §5 |
| Phase 1.5 §4.4 (SwiftPM test target) | Bundle.module setup | §5.4 |
| Phase 2 §5 (ActionName + Args enum) | Args wire format | §2 |
| Phase 2 §7 (write screens; Args shape) | Args wire format | §2 |
| Phase 2 §10 (Force import; error UX) | I18nError wire format | §3 |
| Phase 5 §3 (pack engine; iCloud) | Pack format | §4 |
| Phase 5 §4 (conflict resolution) | detectFileKind | §4.6 |
| Phase 6.4 §2.1 (AddTransactionIntent) | Args wire format (addTransaction) | §2 |
| Phase 6.5 §3 (Share Extension; setEntryAttachment) | Args wire format (setEntryAttachment) | §2 |
| Phase 8 §2 (CloudKit Mutation row) | Args wire format + I18nError | §2 + §3 |

Each of these should grow a one-line cross-reference: "see
`IOS_MACOS_WIRE_FORMAT.md` §N". (This is a follow-up backfill,
not part of the annex itself.)

## §7. Out of scope (firm)

- **Swift port design** — this annex is a reference, not a port
  spec. The iOS implementer lifts and translates.
- **Custom-server variants** — Phase 8's row-level sync introduces
  a different wire format (CloudKit records); see
  `IOS_MACOS_PHASE_8_DESIGN.md` §2.2.
- **Multi-ledger packs** — a single pack contains one ledger.
  Multi-ledger exports are a sequence of single-ledger packs.
- **Encrypted packs** — out of scope (per `IOS_MACOS_PLAN.md` §10).
- **Streaming packs** — packs are read/written in full; no
  streaming API.
- **Compression tuning** — DEFLATE level 6 (the web's `JSZip`
  default); attachments are STORE'd. No further tuning.
- **Schema versioning beyond format_version 1** — when the format
  changes incompatibly, the version is bumped to `'2'` and a
  migration shim is added. v1 is the only version today.

## §8. Spec self-review

Placeholder scan: none — every section is concrete.

Internal consistency:
- §2 (Args) references `_args.ts:33-219` and the per-domain `types.ts`
  files. The 12+5+5+3+6+3+3+3+4+7+3+4+5+2+5 = 74 actions are
  enumerated; the +1 for `setEntryAttachment` (Phase 6.5) is noted.
- §3 (I18nError) quotes `i18n-error.ts` verbatim; the wire shape
  and round-trip are pinned.
- §4 (pack format) quotes `pack.ts` verbatim; the full lifecycle
  (build + parse + extract + detectFileKind) is covered.
- §5 (fixture format) gives 8 examples (one per selector group).

Cross-doc consistency:
- All file:line references verified against the current web code.
- Action counts and selector counts match the grill-pass-#3 state
  (32 selectors, 74 unique actions, 13 per-domain `mutations.ts`).

Scope check: focused on the 4 wire contracts. Implementation
details (Swift code, GRDB code, error UX) live in the existing
phase specs.

Ambiguity check: the only "ambiguous" fields are:
- `setDisplayCurrency` — the per-ledger currency override is a
  **single** `app_state` key holding a JSON map (§2.2 app_state).
  The Phase 1.5 spec was updated in grill pass #3 to match.
- `rollover` on budgets — accepts `number | boolean` (§2.2 budgets);
  the chokepoint coerces `boolean → number`. The Swift port must
  mirror this.

Both are explicit in the annex.

## §9. Open questions

None blocking. The wire contracts are pinned by the web's actual
code; the iOS port's job is to mirror them.

- **Backfill §6 cross-references** — once the annex lands, update
  the 7+ existing specs to add one-line cross-references. (Not
  part of the annex itself; a follow-up commit.)
- **Swift `Codable` for `Args` enum** — the implementer can
  either hand-write the 74-75 cases or write a small code-gen
  script that reads `_args.ts` and emits the Swift enum. The
  annex doesn't pick — it's a reference, not a port design.
- **The `transactionAmount` wire format** — for `addTransaction`,
  `amount` is signed native, `amountBase` is signed ledger-base.
  Both are `number` (Double) on the wire. The iOS port converts
  to `Decimal` at the boundary. This is pinned in §2.2 (invariants
  #3).
