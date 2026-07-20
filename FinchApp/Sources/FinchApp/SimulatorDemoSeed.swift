import Foundation
import FinchCore
import GRDB

/// Simulator-only demo data — a Personal/USD ledger with accounts (+groups),
/// multi-level categories, tags, a rich global merchant catalog, budgets
/// (+groups), and ~2 months of transactions, plus three more ledgers (Travel/EUR,
/// Business/USD, UK Flat/GBP) and a spread of FX rates so the ledger switcher,
/// category tree, Merchants page, and Currencies page all have real data. NOT
/// shipped to real users: the call site in `FinchStore.bootstrap()` is gated by
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

        // Subcategories (parent_id) — categories nest up to three levels, so the
        // picker/tree renders a real hierarchy. Budgets over a PARENT roll up their
        // descendants' spend (expandDescendants), so these still count toward the
        // Dining/Transport/Shopping/Health budgets below.
        let subcategories: [(id: String, name: String, parent: String)] = [
            ("cat-dining-restaurants",   "Restaurants",     "cat-dining"),
            ("cat-dining-coffee",        "Coffee Shops",    "cat-dining"),
            ("cat-dining-fastfood",      "Fast Food",       "cat-dining"),
            ("cat-transport-fuel",       "Fuel",            "cat-transport"),
            ("cat-transport-rideshare",  "Rideshare",       "cat-transport"),
            ("cat-transport-transit",    "Public Transit",  "cat-transport"),
            ("cat-shopping-clothing",    "Clothing",        "cat-shopping"),
            ("cat-shopping-electronics", "Electronics",     "cat-shopping"),
            ("cat-shopping-home",        "Home",            "cat-shopping"),
            ("cat-health-pharmacy",      "Pharmacy",        "cat-health"),
            ("cat-health-fitness",       "Fitness",         "cat-health"),
        ]
        // A third level under Shopping › Home (the deepest the 3-level cap allows).
        let subSubcategories: [(id: String, name: String, parent: String)] = [
            ("cat-shopping-home-furniture", "Furniture", "cat-shopping-home"),
            ("cat-shopping-home-decor",     "Decor",     "cat-shopping-home"),
        ]
        for c in subcategories + subSubcategories {
            try apply("createCategory", [
                "id": .string(c.id), "ledgerId": .string("personal"),
                "name": .string(c.name), "type": .string("expense"),
                "parentId": .string(c.parent)])
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
        // A savings goal (income budget, tracked via contributions) so the goal
        // surfaces — Contribute swipe, Goal section, saved progress — are demo-able.
        try apply("createBudget", [
            "ledgerId": .string("personal"), "name": .string("Vacation Fund"),
            "type": .string("income"), "amount": .double(2_000), "saved": .double(650),
            "startDate": .string(monthStart(3))])

        for b in budgets {
            var args: [String: JSONValue] = [
                "ledgerId": .string("personal"), "name": .string(b.name), "type": .string("expense"),
                "amount": .double(b.amount), "frequency": .string("monthly"),
                "startDate": .string(monthStart(3)),
                "categoryIds": .array([.string(b.cat)])]
            if let g = b.group { args["groupId"] = .string(g) }
            try apply("createBudget", args)
        }

        // Tags (parity palette) applied to several transactions below.
        let tags: [(id: String, name: String, color: String)] = [
            ("tag-reimbursable", "reimbursable",   "#00a5da"),
            ("tag-subscription", "subscription",   "#7d7df9"),
            ("tag-business",     "business",        "#00af67"),
            ("tag-vacation",     "vacation",        "#ba8600"),
            ("tag-tax",          "tax-deductible",  "#e0533d"),
            ("tag-gift",         "gift",            "#c766d6"),
            ("tag-medical",      "medical",         "#2ba3a3"),
            ("tag-online",       "online",          "#8a8f99"),
        ]
        for t in tags {
            try apply("createTag", ["id": .string(t.id), "ledgerId": .string("personal"),
                                    "name": .string(t.name), "color": .string(t.color)])
        }

        // Merchants (counterparties). Names match the transaction merchants below,
        // so the catalog resolves each merchant's transactions by name (populating
        // the Merchants page with counts); a few are marked verified.
        let merchants: [(id: String, name: String, verified: Bool)] = [
            ("cp-wholefoods", "Whole Foods",        true),
            ("cp-traderjoes", "Trader Joe's",       true),
            ("cp-acme",       "Acme Corp Payroll",  true),
            ("cp-starbucks",  "Starbucks",          false),
            ("cp-bluebottle", "Blue Bottle Coffee", false),
            ("cp-shell",      "Shell Gas",          false),
            ("cp-netflix",    "Netflix",            false),
            ("cp-spotify",    "Spotify",            false),
            ("cp-uber",       "Uber",               false),
            ("cp-lyft",       "Lyft",               false),
            ("cp-costco",     "Costco",             false),
            // A wider catalog (global — shared across every ledger). Names match the
            // transactions added below so each shows a real count on the Merchants page.
            ("cp-amazon",     "Amazon",             true),
            ("cp-target",     "Target",             true),
            ("cp-apple",      "Apple Store",        true),
            ("cp-adobe",      "Adobe",              true),
            ("cp-tesco",      "Tesco",              true),
            ("cp-chevron",    "Chevron",            false),
            ("cp-homedepot",  "Home Depot",         false),
            ("cp-ikea",       "IKEA",               false),
            ("cp-westelm",    "West Elm",           false),
            ("cp-walgreens",  "Walgreens",          false),
            ("cp-doordash",   "DoorDash",           false),
            ("cp-equinox",    "Equinox",            false),
            ("cp-delta",      "Delta Airlines",     false),
            ("cp-googleads",  "Google Ads",         false),
            ("cp-sainsburys", "Sainsbury's",        false),
        ]
        for m in merchants {
            try apply("createCounterparty", ["id": .string(m.id), "ledgerId": .string("personal"), "name": .string(m.name)])
            if m.verified { try apply("verifyCounterparty", ["id": .string(m.id)]) }
        }

        // ~3 months of transactions. Expenses negative, income positive.
        let txns: [(d: Int, acct: String, amt: Double, merchant: String, cat: String,
                    kind: String?, status: String?, tags: [String]?)] = [
            (1,  "credit",   -32.40, "Amazon",             "cat-shopping-electronics",    nil,      nil,       ["tag-online"]),
            (2,  "credit",   -42.18, "Whole Foods",        "cat-groceries",               nil,      "pending", ["tag-reimbursable"]),
            (2,  "everyday",  -58.20, "Target",            "cat-groceries",               nil,      nil,       nil),
            (3,  "credit",   -16.40, "Blue Bottle Coffee", "cat-dining-coffee",           nil,      "pending", nil),
            (4,  "everyday", -1_850, "Apartment Rent",     "cat-rent",                    nil,      nil,       nil),
            (4,  "credit",  -410.00, "Apple Store",        "cat-shopping-electronics",    nil,      nil,       ["tag-tax"]),
            (5,  "everyday",  4_200, "Acme Corp Payroll",  "cat-salary",                  nil,      nil,       nil),
            (6,  "credit",   -28.75, "Shell Gas",          "cat-transport-fuel",          nil,      nil,       nil),
            (7,  "cash",     -12.00, "Food Truck",         "cat-dining-fastfood",         nil,      nil,       nil),
            (8,  "credit",   -64.99, "Uniqlo",             "cat-shopping-clothing",       nil,      nil,       nil),
            (9,  "credit",    -9.99, "Netflix",            "cat-entertainment",           nil,      nil,       ["tag-subscription"]),
            (9,  "credit",   -44.10, "Chevron",            "cat-transport-fuel",          nil,      nil,       nil),
            (10, "everyday",  -88.30, "PG&E Utilities",    "cat-utilities",               nil,      nil,       nil),
            (11, "credit",    64.99, "Nordstrom Refund",   "cat-shopping",                "refund", nil,       ["tag-vacation"]),
            (12, "credit",   -53.20, "Trader Joe's",       "cat-groceries",               nil,      nil,       nil),
            (13, "credit",   -22.50, "Chipotle",           "cat-dining-restaurants",      nil,      nil,       nil),
            (14, "credit",   -31.00, "Uber",               "cat-transport-rideshare",     nil,      nil,       ["tag-business"]),
            (15, "credit",   -18.75, "DoorDash",           "cat-dining-fastfood",         nil,      nil,       nil),
            (16, "credit",  -120.00, "Nordstrom",          "cat-shopping-clothing",       nil,      nil,       ["tag-vacation"]),
            (17, "cash",     -18.00, "Farmers Market",     "cat-groceries",               nil,      nil,       nil),
            (18, "credit",  -240.00, "IKEA",               "cat-shopping-home-furniture", nil,      nil,       ["tag-gift"]),
            (19, "credit",   -45.60, "CVS Pharmacy",       "cat-health-pharmacy",         nil,      nil,       ["tag-reimbursable"]),
            (20, "everyday",  4_200, "Acme Corp Payroll",  "cat-salary",                  nil,      nil,       nil),
            (21, "credit",   -38.40, "Safeway",            "cat-groceries",               nil,      nil,       nil),
            (22, "credit",   -68.00, "West Elm",           "cat-shopping-home-decor",     nil,      nil,       nil),
            (23, "credit",   -14.25, "Starbucks",          "cat-dining-coffee",           nil,      nil,       nil),
            (24, "cash",     -12.50, "BART",               "cat-transport-transit",       nil,      nil,       nil),
            (25, "credit",   -19.99, "Spotify",            "cat-entertainment",           nil,      nil,       ["tag-subscription"]),
            (26, "credit",   -27.30, "Walgreens",          "cat-health-pharmacy",         nil,      nil,       ["tag-medical"]),
            (27, "credit",   -27.80, "Lyft",               "cat-transport-rideshare",     nil,      nil,       ["tag-business", "tag-reimbursable"]),
            (28, "credit",   -85.00, "Home Depot",         "cat-shopping-home",           nil,      nil,       nil),
            (30, "credit",   -58.10, "Whole Foods",        "cat-groceries",               nil,      nil,       nil),
            (33, "credit",   -72.00, "AMC Theatres",       "cat-entertainment",           nil,      nil,       nil),
            (35, "everyday",  4_200, "Acme Corp Payroll",  "cat-salary",                  nil,      nil,       nil),
            (38, "credit",   -41.30, "Trader Joe's",       "cat-groceries",               nil,      nil,       nil),
            (40, "credit",  -180.00, "Equinox",            "cat-health-fitness",          nil,      nil,       nil),
            (42, "credit",   -33.50, "Olive Garden",       "cat-dining-restaurants",      nil,      nil,       nil),
            (46, "credit",   -95.00, "Best Buy",           "cat-shopping-electronics",    nil,      nil,       ["tag-business"]),
            (50, "everyday", -1_850, "Apartment Rent",     "cat-rent",                    nil,      nil,       nil),
            (55, "credit",   -49.90, "Costco",             "cat-groceries",               nil,      nil,       ["tag-reimbursable"]),
            (60, "credit",   -24.00, "Shell Gas",          "cat-transport-fuel",          nil,      nil,       nil),
            (68, "credit",   -61.40, "REI",                "cat-shopping",                nil,      nil,       ["tag-vacation"]),
        ]
        for t in txns {
            var args: [String: JSONValue] = [
                "ledgerId": .string("personal"), "accountId": .string(t.acct),
                "amount": .double(t.amt), "merchant": .string(t.merchant),
                "categoryId": .string(t.cat), "date": .string(ymd(t.d)), "time": .string("12:00")]
            if let k = t.kind { args["kind"] = .string(k) }
            if let s = t.status { args["status"] = .string(s) }
            if let tg = t.tags { args["tagIds"] = .array(tg.map { .string($0) }) }
            try apply("addTransaction", args)
        }

        // A real posted transfer (Everyday → Savings) so the transfer kind shows in the feed.
        try apply("createTransfer", [
            "fromAccountId": .string("everyday"), "toAccountId": .string("savings"),
            "fromAmount": .double(500), "date": .string(ymd(15)), "time": .string("12:00")])

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

        // An installment plan so the Scheduled tab shows installment progress.
        try apply("createScheduled", [
            "ledgerId": .string("personal"), "name": .string("Furniture Plan"),
            "type": .string("expense"), "amount": .double(120), "frequency": .string("monthly"),
            "accountId": .string("credit"), "dayOfMonth": .double(12),
            "startDate": .string(monthStart(2)), "category": .string("cat-shopping"),
            "installmentTotal": .double(12)])

        // A second, EUR-based ledger ("Travel") so the ledger switcher + Manage
        // ledgers aren't single-entry. Kept lightweight (accounts + categories +
        // a few transactions); Personal stays the default/active ledger.
        try apply("createLedger", ["id": .string("travel"), "name": .string("Travel"), "base": .string("EUR")])
        // EUR↔USD rate (USD is the hub; only non-USD stored) so the Travel ledger converts.
        try apply("setExchangeRate", ["date": .string(ymd(1)), "currency": .string("EUR"), "rate": .double(1.08)])
        // A spread of reference rates (USD-per-unit) so the Currencies page shows
        // several rated currencies (incl. GBP for the UK Flat ledger below); a few
        // are marked tracked, which drives the daily Frankfurter fetch list.
        let fxRates: [(code: String, rate: Double)] = [
            ("GBP", 1.27), ("JPY", 0.0067), ("CAD", 0.74),
            ("AUD", 0.66), ("CHF", 1.12), ("CNY", 0.14),
        ]
        for r in fxRates {
            try apply("setExchangeRate", ["date": .string(ymd(1)), "currency": .string(r.code), "rate": .double(r.rate)])
        }
        try apply("setTrackedCurrencies", ["codes": .array(["EUR", "GBP", "JPY", "CAD"].map { .string($0) })])
        // Account ids are a GLOBAL primary key (not per-ledger) — these must not
        // reuse the Personal ledger's ids ("travel-card" already exists there; the
        // collision used to abort the whole Travel section mid-seed, silently, via
        // bootstrap()'s do/catch).
        let travelAccounts: [(id: String, name: String, type: String, opening: Double)] = [
            ("tvl-checking", "Travel Checking", "savings", 2_000),
            ("tvl-card", "Travel Card", "credit_card", 0),
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
            (3,  "tvl-card",     -420.00, "Lufthansa",     "tcat-flights"),
            (5,  "tvl-card",     -680.00, "Hotel Adlon",   "tcat-lodging"),
            (6,  "tvl-card",      -54.00, "Café Einstein", "tcat-food"),
            (8,  "tvl-card",      -32.00, "Museum Pass",   "tcat-activities"),
            (10, "tvl-checking", -120.00, "Train Tickets", "tcat-activities"),
            (12, "tvl-card",      -75.00, "Brauhaus",      "tcat-food"),
        ]
        for t in travelTxns {
            try apply("addTransaction", [
                "ledgerId": .string("travel"), "accountId": .string(t.acct),
                "amount": .double(t.amt), "merchant": .string(t.merchant),
                "categoryId": .string(t.cat), "date": .string(ymd(t.d)), "time": .string("12:00")])
        }

        // A third ledger ("Business", USD) so the switcher has a same-currency
        // sibling to Personal — exercises per-ledger Categories/Tags (incl. their own
        // nesting) while sharing the global Merchants + Currencies. Lightweight.
        try apply("createLedger", ["id": .string("business"), "name": .string("Business"), "base": .string("USD")])
        let bizAccounts: [(id: String, name: String, type: String, opening: Double)] = [
            ("biz-checking", "Business Checking", "cash", 12_000),
            ("biz-card", "Business Card", "credit_card", 0),
        ]
        for a in bizAccounts {
            try apply("createAccount", [
                "id": .string(a.id), "ledgerId": .string("business"), "name": .string(a.name),
                "type": .string(a.type), "currency": .string("USD"), "openingBalance": .double(a.opening)])
        }
        let bizCategories: [(id: String, name: String, kind: String)] = [
            ("bcat-income", "Client Income", "income"),
            ("bcat-software", "Software", "expense"),
            ("bcat-office", "Office", "expense"),
            ("bcat-travel", "Travel", "expense"),
            ("bcat-marketing", "Marketing", "expense"),
        ]
        for c in bizCategories {
            try apply("createCategory", [
                "id": .string(c.id), "ledgerId": .string("business"),
                "name": .string(c.name), "type": .string(c.kind)])
        }
        // Business categories nest too (Software › SaaS / One-time).
        for (id, name) in [("bcat-software-saas", "SaaS"), ("bcat-software-onetime", "One-time")] {
            try apply("createCategory", [
                "id": .string(id), "ledgerId": .string("business"), "name": .string(name),
                "type": .string("expense"), "parentId": .string("bcat-software")])
        }
        let bizTags: [(id: String, name: String, color: String)] = [
            ("btag-billable", "billable", "#00af67"),
            ("btag-q3", "Q3", "#7d7df9"),
        ]
        for t in bizTags {
            try apply("createTag", ["id": .string(t.id), "ledgerId": .string("business"),
                                    "name": .string(t.name), "color": .string(t.color)])
        }
        let bizTxns: [(d: Int, acct: String, amt: Double, merchant: String, cat: String, tags: [String]?)] = [
            (2,  "biz-checking",  6_500, "Client Retainer", "bcat-income",         nil),
            (4,  "biz-card",       -52.99, "Adobe",          "bcat-software-saas",  ["btag-billable"]),
            (5,  "biz-card",       -99.00, "Notion",         "bcat-software-saas",  nil),
            (9,  "biz-card",      -240.00, "Delta Airlines", "bcat-travel",         ["btag-q3"]),
            (12, "biz-card",      -180.00, "Google Ads",     "bcat-marketing",      nil),
            (15, "biz-card",       -64.00, "WeWork",         "bcat-office",         nil),
        ]
        for t in bizTxns {
            var args: [String: JSONValue] = [
                "ledgerId": .string("business"), "accountId": .string(t.acct),
                "amount": .double(t.amt), "merchant": .string(t.merchant),
                "categoryId": .string(t.cat), "date": .string(ymd(t.d)), "time": .string("12:00")]
            if let tg = t.tags { args["tagIds"] = .array(tg.map { .string($0) }) }
            try apply("addTransaction", args)
        }

        // A fourth ledger ("UK Flat", GBP) — a non-USD/non-EUR base so the GBP rate
        // seeded above and the display-currency conversion path get exercised.
        try apply("createLedger", ["id": .string("ukflat"), "name": .string("UK Flat"), "base": .string("GBP")])
        let ukAccounts: [(id: String, name: String, type: String, opening: Double)] = [
            ("uk-current", "UK Current", "cash", 1_500),
            ("uk-card", "UK Card", "credit_card", 0),
        ]
        for a in ukAccounts {
            try apply("createAccount", [
                "id": .string(a.id), "ledgerId": .string("ukflat"), "name": .string(a.name),
                "type": .string(a.type), "currency": .string("GBP"), "openingBalance": .double(a.opening)])
        }
        let ukCategories: [(id: String, name: String)] = [
            ("ucat-rent", "Flat Rent"), ("ucat-council", "Council Tax"),
            ("ucat-energy", "Energy"), ("ucat-groceries", "Groceries"),
        ]
        for c in ukCategories {
            try apply("createCategory", [
                "id": .string(c.id), "ledgerId": .string("ukflat"),
                "name": .string(c.name), "type": .string("expense")])
        }
        let ukTxns: [(d: Int, acct: String, amt: Double, merchant: String, cat: String)] = [
            (3,  "uk-current", -1_200.00, "Flat Rent",   "ucat-rent"),
            (6,  "uk-card",       -82.40, "Tesco",       "ucat-groceries"),
            (8,  "uk-card",       -60.00, "British Gas", "ucat-energy"),
            (10, "uk-current",   -145.00, "Council Tax", "ucat-council"),
            (12, "uk-card",       -38.50, "Sainsbury's", "ucat-groceries"),
        ]
        for t in ukTxns {
            try apply("addTransaction", [
                "ledgerId": .string("ukflat"), "accountId": .string(t.acct),
                "amount": .double(t.amt), "merchant": .string(t.merchant),
                "categoryId": .string(t.cat), "date": .string(ymd(t.d)), "time": .string("12:00")])
        }
    }
}
