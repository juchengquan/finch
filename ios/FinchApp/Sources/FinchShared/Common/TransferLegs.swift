import FinchCore

/// The legs of transfers between your own accounts, as they appear in a list of rows.
///
/// The feed and the account list show a row per account leg, so one $250 Checking →
/// Savings transfer is two rows: −250 on Checking and +250 on Savings. Pure (no store),
/// so the month figures and the row titles share one reading of "which rows belong to
/// one transfer" and it is unit-tested.
///
/// Only `kind == "transfer"` rows carry a `transferGroupId` (the projection stamps it
/// on an entry with two or more account legs). A cross-ledger transfer is its own kind,
/// `interledger`, with one leg per ledger — money really leaving or entering this one —
/// so it is never paired here.
enum TransferLegs {
    /// Ids of the rows whose transfer has EVERY leg in `txns`. Those legs moved money
    /// between rows of the same set, so a total over the set must not count them: they
    /// net to zero, and summing them by sign adds the amount to both in and out.
    ///
    /// A leg whose partner is absent — one account's list, or a feed filtered to one
    /// account — is not internal to that set; it is money that set gained or lost.
    static func complete(_ txns: [Tx]) -> Set<String> {
        var legs: [String: [Tx]] = [:]
        for t in txns {
            guard let gid = t.transferGroupId else { continue }
            legs[gid, default: []].append(t)
        }
        var ids = Set<String>()
        for group in legs.values where group.count >= max(2, group[0].accountLegCount ?? 2) {
            ids.formUnion(group.map(\.id))
        }
        return ids
    }

    /// Each transfer leg's id → the OTHER account of its transfer, for a two-account
    /// transfer whose legs are both in `txns`. Feeds the row title ("To Savings" on the
    /// Checking leg). Absent for anything else, so the title falls back to "Transfer".
    static func peers(_ txns: [Tx]) -> [String: String] {
        var legs: [String: [Tx]] = [:]
        for t in txns {
            guard let gid = t.transferGroupId else { continue }
            legs[gid, default: []].append(t)
        }
        var out: [String: String] = [:]
        for group in legs.values where group.count == 2 && group[0].account != group[1].account {
            out[group[0].id] = group[1].account
            out[group[1].id] = group[0].account
        }
        return out
    }
}
