import SwiftUI
import FinchCore

/// The Budgets-tab health header: expense-budget remaining (hero) + overall
/// color-banded bar + spent/budget caption + an "N over" badge, with a separate
/// goals line. All amounts route store.displayMoneyBase (privacy-aware); the bar
/// is a ratio (no maskable amount). Replaces the old two-number StatusSummaryRow.
struct BudgetSummaryCard: View {
    @EnvironmentObject private var store: FinchStore
    let summary: BudgetSummary

    private var overallPct: Int {
        summary.budgetBase > 0 ? Int((summary.spentBase / summary.budgetBase * 100).rounded()) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if summary.hasSpend {
                HStack(alignment: .firstTextBaseline) {
                    if summary.remainingBase < 0 {
                        HStack(spacing: 4) {
                            Text(store.displayMoneyBase(-summary.remainingBase))
                                .font(.title2.weight(.semibold)).foregroundStyle(.red)
                            Text("over").font(.subheadline).foregroundStyle(.red)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text(store.displayMoneyBase(summary.remainingBase))
                                .font(.title2.weight(.semibold))
                            Text("left to spend").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if summary.overCount > 0 {
                        Label("\(summary.overCount) over", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(.red)
                    }
                }
                ProgressView(value: min(summary.spentBase / max(summary.budgetBase, 0.01), 1.0))
                    .tint(BudgetThreshold.color(pct: overallPct))
                Text("\(store.displayMoneyBase(summary.spentBase)) spent · of \(store.displayMoneyBase(summary.budgetBase))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if summary.hasGoals {
                if summary.hasSpend { Divider() }
                Text("Income · \(store.displayMoneyBase(summary.goalSavedBase)) of \(store.displayMoneyBase(summary.goalTargetBase)) saved")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
