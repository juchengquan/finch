import Foundation
import FinchCore
import GRDB

/// Simulator-only demo data — a Personal/USD ledger with accounts (+groups),
/// categories, budgets (+groups), and ~2 months of transactions. NOT shipped to real
/// users: the call site in `FinchStore.bootstrap()` is gated by
/// `#if targetEnvironment(simulator)`.
///
/// To remove the demo entirely: delete this file and the `SimulatorDemoSeed.seed(...)`
/// line in FinchStore.swift (real devices already fall back to `seedMinimalStarter`).
enum SimulatorDemoSeed {
    static func seed(_ q: DatabaseQueue) throws {
        func apply(_ action: String, _ args: [String: JSONValue]) throws {
            try Apply.apply(dbQueue: q, action: action, args: Args(args))
        }
        let cal = Calendar.current
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = cal.timeZone
        let now = Date()
        func ymd(_ daysAgo: Int) -> String {
            df.string(from: cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now)
        }
        // First day of the month `monthsAgo` before now — a budget start that
        // predates every seeded transaction (oldest is 68 days ≈ 2.3 months back),
        // so the current monthly window captures real month-to-date spend instead
        // of starting "today" and counting nothing. See cycleWindow/budgetProgress.
        func monthStart(_ monthsAgo: Int) -> String {
            let base = cal.date(byAdding: .month, value: -monthsAgo, to: now) ?? now
            let comps = cal.dateComponents([.year, .month], from: base)
            return df.string(from: cal.date(from: comps) ?? base)
        }

        try apply("createLedger", ["id": .string("personal"), "name": .string("Personal"), "base": .string("USD")])
        try apply("setDefaultLedger", ["id": .string("personal")])

        // Account groups so the Accounts page shows grouped sections + subtotals.
        let accountGroups: [(id: String, name: String)] = [
            ("grp-cash", "Cash & Checking"),
            ("grp-savings", "Savings & Investments"),
            ("grp-retirement", "Retirement"),
            ("grp-credit", "Credit Cards"),
        ]
        for g in accountGroups {
            try apply("createAccountGroup", [
                "id": .string(g.id), "ledgerId": .string("personal"), "name": .string(g.name)])
        }

        // Accounts (with opening balances + group). Types limited to the valid set.
        let accounts: [(id: String, name: String, type: String, opening: Double, group: String)] = [
            ("cash", "Cash", "cash", 180, "grp-cash"),
            ("everyday", "Everyday", "savings", 3_200, "grp-cash"),
            ("checking", "Checking", "cash", 2_400, "grp-cash"),
            ("savings", "Savings", "savings", 15_400, "grp-savings"),
            ("brokerage", "Brokerage", "investment", 8_600, "grp-savings"),
            ("retire-401k", "401(k)", "investment", 42_000, "grp-retirement"),
            ("roth-ira", "Roth IRA", "investment", 18_500, "grp-retirement"),
            ("credit", "Credit Card", "credit_card", 0, "grp-credit"),
            ("travel-card", "Travel Card", "credit_card", 0, "grp-credit"),
        ]
        for a in accounts {
            try apply("createAccount", [
                "id": .string(a.id), "ledgerId": .string("personal"), "name": .string(a.name),
                "type": .string(a.type), "currency": .string("USD"), "openingBalance": .double(a.opening),
                "groupId": .string(a.group)])
        }

        // Categories (explicit ids so transactions/budgets can reference them).
        let categories: [(id: String, name: String, kind: String)] = [
            ("cat-groceries", "Groceries", "expense"),
            ("cat-dining", "Dining", "expense"),
            ("cat-transport", "Transport", "expense"),
            ("cat-shopping", "Shopping", "expense"),
            ("cat-entertainment", "Entertainment", "expense"),
            ("cat-utilities", "Utilities", "expense"),
            ("cat-rent", "Rent", "expense"),
            ("cat-health", "Health", "expense"),
            ("cat-salary", "Salary", "income"),
        ]
        for c in categories {
            try apply("createCategory", [
                "id": .string(c.id), "ledgerId": .string("personal"),
                "name": .string(c.name), "type": .string(c.kind)])
        }

        // Budget groups.
        let budgetGroups: [(id: String, name: String)] = [
            ("bgg-essentials", "Essentials"),
            ("bgg-lifestyle", "Lifestyle"),
        ]
        for g in budgetGroups {
            try apply("createBudgetGroup", [
                "id": .string(g.id), "ledgerId": .string("personal"), "name": .string(g.name)])
        }

        // Monthly budgets over a few categories.
        let budgets: [(name: String, amount: Double, cat: String, group: String?)] = [
            ("Rent", 1500, "cat-rent", "bgg-essentials"),
            ("Groceries", 600, "cat-groceries", "bgg-essentials"),
            ("Utilities", 150, "cat-utilities", "bgg-essentials"),
            ("Transport", 200, "cat-transport", "bgg-essentials"),
            ("Dining", 300, "cat-dining", "bgg-lifestyle"),
            ("Shopping", 400, "cat-shopping", "bgg-lifestyle"),
            ("Entertainment", 120, "cat-entertainment", "bgg-lifestyle"),
            ("Health", 100, "cat-health", nil),
        ]
        for b in budgets {
            var args: [String: JSONValue] = [
                "ledgerId": .string("personal"), "name": .string(b.name), "type": .string("expense"),
                "amount": .double(b.amount), "frequency": .string("monthly"),
                "startDate": .string(monthStart(3)),
                "categoryIds": .array([.string(b.cat)])]
            if let g = b.group { args["groupId"] = .string(g) }
            try apply("createBudget", args)
        }

        // ~3 months of transactions. Expenses negative, income positive.
        let txns: [(d: Int, acct: String, amt: Double, merchant: String, cat: String)] = [
            (2, "credit", -42.18, "Whole Foods", "cat-groceries"),
            (3, "credit", -16.40, "Blue Bottle Coffee", "cat-dining"),
            (4, "everyday", -1_850, "Apartment Rent", "cat-rent"),
            (5, "everyday", 4_200, "Acme Corp Payroll", "cat-salary"),
            (6, "credit", -28.75, "Shell Gas", "cat-transport"),
            (7, "cash", -12.00, "Food Truck", "cat-dining"),
            (8, "credit", -64.99, "Uniqlo", "cat-shopping"),
            (9, "credit", -9.99, "Netflix", "cat-entertainment"),
            (10, "everyday", -88.30, "PG&E Utilities", "cat-utilities"),
            (12, "credit", -53.20, "Trader Joe's", "cat-groceries"),
            (13, "credit", -22.50, "Chipotle", "cat-dining"),
            (14, "credit", -31.00, "Uber", "cat-transport"),
            (16, "credit", -120.00, "Nordstrom", "cat-shopping"),
            (17, "cash", -18.00, "Farmers Market", "cat-groceries"),
            (19, "credit", -45.60, "CVS Pharmacy", "cat-health"),
            (20, "everyday", 4_200, "Acme Corp Payroll", "cat-salary"),
            (21, "credit", -38.40, "Safeway", "cat-groceries"),
            (23, "credit", -14.25, "Starbucks", "cat-dining"),
            (25, "credit", -19.99, "Spotify", "cat-entertainment"),
            (27, "credit", -27.80, "Lyft", "cat-transport"),
            (30, "credit", -58.10, "Whole Foods", "cat-groceries"),
            (33, "credit", -72.00, "AMC Theatres", "cat-entertainment"),
            (35, "everyday", 4_200, "Acme Corp Payroll", "cat-salary"),
            (38, "credit", -41.30, "Trader Joe's", "cat-groceries"),
            (42, "credit", -33.50, "Olive Garden", "cat-dining"),
            (46, "credit", -95.00, "Best Buy", "cat-shopping"),
            (50, "everyday", -1_850, "Apartment Rent", "cat-rent"),
            (55, "credit", -49.90, "Costco", "cat-groceries"),
            (60, "credit", -24.00, "Shell Gas", "cat-transport"),
            (68, "credit", -61.40, "REI", "cat-shopping"),
        ]
        for t in txns {
            try apply("addTransaction", [
                "ledgerId": .string("personal"), "accountId": .string(t.acct),
                "amount": .double(t.amt), "merchant": .string(t.merchant),
                "categoryId": .string(t.cat), "date": .string(ymd(t.d)), "time": .string("12:00")])
        }

        // Recurring scheduled templates (bills, subscriptions, salary, a transfer)
        // so the Scheduled tab is populated. Amounts are positive magnitudes —
        // `kind` drives the sign when posted. Transfers carry `from` (source);
        // `acct` is the destination. Start a few months back so the next run is
        // a real upcoming date.
        let scheduled: [(name: String, type: String, amount: Double, freq: String,
                         acct: String, from: String?, cat: String?, day: Int)] = [
            ("Apartment Rent",     "expense",  1_850, "monthly",   "everyday", nil,        "cat-rent",          1),
            ("Acme Corp Payroll",  "income",   4_200, "monthly",   "everyday", nil,        "cat-salary",        5),
            ("Transfer to Savings","transfer",   500, "monthly",   "savings",  "everyday", nil,                 6),
            ("Netflix",            "expense",   9.99, "monthly",   "credit",   nil,        "cat-entertainment", 9),
            ("PG&E Utilities",     "expense",  88.30, "monthly",   "everyday", nil,        "cat-utilities",    10),
            ("Gym Membership",     "expense",     40, "monthly",   "credit",   nil,        "cat-health",       15),
            ("Phone Bill",         "expense",     55, "monthly",   "credit",   nil,        "cat-utilities",    18),
            ("Car Insurance",      "expense",    180, "quarterly", "credit",   nil,        "cat-transport",    20),
            ("Spotify",            "expense",  19.99, "monthly",   "credit",   nil,        "cat-entertainment",25),
        ]
        for s in scheduled {
            var args: [String: JSONValue] = [
                "ledgerId": .string("personal"), "name": .string(s.name), "type": .string(s.type),
                "amount": .double(s.amount), "frequency": .string(s.freq),
                "accountId": .string(s.acct), "dayOfMonth": .double(Double(s.day)),
                "startDate": .string(monthStart(2)),
            ]
            if let from = s.from { args["fromAccountId"] = .string(from) }
            if let cat = s.cat { args["category"] = .string(cat) }
            try apply("createScheduled", args)
        }

        // A second, EUR-based ledger ("Travel") so the ledger switcher + Manage
        // ledgers aren't single-entry. Kept lightweight (accounts + categories +
        // a few transactions); Personal stays the default/active ledger.
        try apply("createLedger", ["id": .string("travel"), "name": .string("Travel"), "base": .string("EUR")])
        let travelAccounts: [(id: String, name: String, type: String, opening: Double)] = [
            ("travel-checking", "Travel Checking", "savings", 2_000),
            ("travel-card", "Travel Card", "credit_card", 0),
        ]
        for a in travelAccounts {
            try apply("createAccount", [
                "id": .string(a.id), "ledgerId": .string("travel"), "name": .string(a.name),
                "type": .string(a.type), "currency": .string("EUR"), "openingBalance": .double(a.opening)])
        }
        let travelCategories: [(id: String, name: String)] = [
            ("tcat-flights", "Flights"), ("tcat-lodging", "Lodging"),
            ("tcat-food", "Food & Drink"), ("tcat-activities", "Activities"),
        ]
        for c in travelCategories {
            try apply("createCategory", [
                "id": .string(c.id), "ledgerId": .string("travel"),
                "name": .string(c.name), "type": .string("expense")])
        }
        let travelTxns: [(d: Int, acct: String, amt: Double, merchant: String, cat: String)] = [
            (3,  "travel-card",     -420.00, "Lufthansa",     "tcat-flights"),
            (5,  "travel-card",     -680.00, "Hotel Adlon",   "tcat-lodging"),
            (6,  "travel-card",      -54.00, "Café Einstein", "tcat-food"),
            (8,  "travel-card",      -32.00, "Museum Pass",   "tcat-activities"),
            (10, "travel-checking", -120.00, "Train Tickets", "tcat-activities"),
            (12, "travel-card",      -75.00, "Brauhaus",      "tcat-food"),
        ]
        for t in travelTxns {
            try apply("addTransaction", [
                "ledgerId": .string("travel"), "accountId": .string(t.acct),
                "amount": .double(t.amt), "merchant": .string(t.merchant),
                "categoryId": .string(t.cat), "date": .string(ymd(t.d)), "time": .string("12:00")])
        }
    }
}
