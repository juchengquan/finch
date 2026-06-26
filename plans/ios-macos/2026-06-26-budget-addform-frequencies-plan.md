# Budget add-form frequencies — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline). Checkbox steps.

**Goal:** Offer all 6 budget frequencies in the create/edit form (add daily + biweekly).

**Architecture:** One-line list change in `BudgetSheet`; backend already accepts the 6.

Spec: `plans/ios-macos/2026-06-26-budget-addform-frequencies-design.md`.

## Global Constraints
- `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; builds: FinchApp (iOS) + FinchMac (macOS). No `Co-Authored-By`. No engine change. PR → `feat/frontend`.

### Task 1: Add daily + biweekly to the form

**Files:** Modify `ios/FinchApp/Sources/FinchApp/WriteScreens/BudgetSheet.swift`

- [ ] **Step 1:** Replace `let frequencies = ["weekly", "monthly", "quarterly", "yearly"]` with `let frequencies = ["daily", "weekly", "biweekly", "monthly", "quarterly", "yearly"]`.
- [ ] **Step 2:** Build iOS + macOS — both `** BUILD SUCCEEDED **`.
- [ ] **Step 3:** Commit `feat(ios): budget create form — offer all 6 frequencies (daily/biweekly)`.

### Task 2: Manual sim
- [ ] Budgets → add budget → Frequency picker lists all 6; create a daily budget → saves.

## Self-review
- Spec coverage: the 6-item list (T1). Type consistency: `frequencies: [String]`, picker `Text($0.capitalized)`. No engine change. ✓
