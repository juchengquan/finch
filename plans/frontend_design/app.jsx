// Main app — assembles the design canvas with all variations + screens,
// wires the Tweaks panel for live theming.

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "palette": "warm",
  "fonts": "editorial",
  "density": "regular",
  "currency": "USD"
}/*EDITMODE-END*/;

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const th = useTheme(t);

  return (
    <>
      <DesignCanvas>
        {/* ────────────────────────────────────────────────────────── */}
        {/* 0 · Overview                                                 */}
        {/* ────────────────────────────────────────────────────────── */}
        <DCSection id="overview" title="Finch · Expense Tracker" subtitle="Editorial flow across four surfaces: Web Mobile + Web Desktop (primary) mirrored by iOS native + iPadOS. Twelve+ screens per platform pair. Reference variations preserved at the bottom.">
          <DCArtboard id="overview-card" label="System brief" width={520} height={580}>
            <SystemOverview th={th}/>
          </DCArtboard>
          <DCArtboard id="palette-card" label="Palette + type" width={420} height={580}>
            <PaletteCard th={th}/>
          </DCArtboard>
          <DCArtboard id="components-card" label="Components" width={480} height={580}>
            <ComponentsCard th={th}/>
          </DCArtboard>
        </DCSection>

        {/* ────────────────────────────────────────────────────────── */}
        {/* ① Web Mobile — PRIMARY                                       */}
        {/* ────────────────────────────────────────────────────────── */}
        <DCSection id="app-webmobile" title="① Web Mobile · Editorial flow" subtitle="Primary surface. Header pattern: profile chip left · centered title · search right. Default tabs: Accounts · Budgets · [+] · Scheduled · Insights. Optional tabs added via Settings → Tab layout.">
          <DCArtboard id="wm-accts"      label="Accounts · home (Activity merged)" width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/accounts"><ScreenAccounts th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="wm-acct-d"     label="Account · detail"                  width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/accounts/chase"><ScreenAccountDetail th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="wm-budgets"    label="Budgets · overview"                width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/budgets"><ScreenBudgets th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="wm-budget-d"   label="Budget · detail"                   width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/budgets/food"><ScreenBudgetDetail th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="wm-sched"      label="Scheduled · calendar"              width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/scheduled"><ScreenScheduled th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="wm-insights"   label="Insights · analytics"              width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/insights"><ScreenInsights th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="wm-activity"   label="Activity · optional tab"           width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/activity"><ScreenActivity th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="wm-goals"      label="Goals · optional tab"              width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/goals"><ScreenGoals th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="wm-subs"       label="Subscriptions · optional tab"      width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/subscriptions"><ScreenSubscriptions th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="wm-add"        label="Add expense · modal"               width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/add"><ScreenAddExpense th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="wm-txd"        label="Transaction detail · drill"        width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/tx/t02"><ScreenTxDetail th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="wm-settings"   label="Settings"                          width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/settings"><ScreenSettings th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="wm-tabs"       label="Settings → Tab layout"             width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/settings/tabs"><ScreenTabLayout th={th}/></MobileWebFrame></DCArtboard>
        </DCSection>

        {/* ────────────────────────────────────────────────────────── */}
        {/* ② Web Desktop — PRIMARY                                     */}
        {/* ────────────────────────────────────────────────────────── */}
        <DCSection id="app-webdesktop" title="② Web Desktop · Editorial flow" subtitle="Primary surface for analysis. Persistent sidebar on every page (Accounts · Budgets · Scheduled · Insights, plus a MORE section with Activity · Goals · Subscriptions · Reports).">
          <DCArtboard id="wd-accts"      label="Accounts · overview"   width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/accounts"><WebAccountsOverview th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="wd-acct-d"     label="Account · detail"      width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/accounts/chase-checking"><WebAccountDetail th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="wd-budgets"    label="Budgets · overview"    width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/budgets"><WebBudgetsOverview th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="wd-budget-d"   label="Budget · detail"       width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/budgets/food-dining"><WebBudgetDetail th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="wd-sched"      label="Scheduled · calendar"  width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/scheduled"><WebScheduledOverview th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="wd-insights"   label="Insights · analytics"  width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/insights"><WebInsightsOverview th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="wd-activity"   label="Activity · optional"   width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/activity"><WebActivityOverview th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="wd-goals"      label="Goals · optional"      width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/goals"><WebGoalsOverview th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="wd-subs"       label="Subscriptions · optional" width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/subscriptions"><WebSubscriptionsOverview th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="wd-txd"        label="Transaction detail"    width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/tx/t02"><WebTxDetail th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="wd-settings"   label="Settings"              width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/settings"><WebSettings th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="wd-tabs"       label="Settings → Tab layout" width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/settings/tabs"><WebTabLayoutPage th={th}/></WebFrame></DCArtboard>
        </DCSection>

        {/* ────────────────────────────────────────────────────────── */}
        {/* ③ iOS native — mirrors web mobile                            */}
        {/* ────────────────────────────────────────────────────────── */}
        <DCSection id="app-ios" title="③ iOS native · Editorial flow" subtitle="Same screens as Web Mobile, wrapped in the native iOS chrome (status bar, dynamic island, home indicator).">
          <DCArtboard id="ios-accts"     label="Accounts · home"          width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenAccounts th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ios-acct-d"    label="Account · detail"         width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenAccountDetail th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ios-budgets"   label="Budgets · overview"       width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenBudgets th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ios-budget-d"  label="Budget · detail"          width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenBudgetDetail th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ios-sched"     label="Scheduled · calendar"     width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenScheduled th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ios-insights"  label="Insights · analytics"     width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenInsights th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ios-activity"  label="Activity · optional"      width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenActivity th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ios-goals"     label="Goals · optional"         width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenGoals th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ios-subs"      label="Subscriptions · optional" width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenSubscriptions th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ios-add"       label="Add expense · modal"      width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenAddExpense th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ios-txd"       label="Transaction detail"       width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenTxDetail th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ios-settings"  label="Settings"                 width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenSettings th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ios-tabs"      label="Settings → Tab layout"    width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenTabLayout th={th}/></PhoneFrame></DCArtboard>
        </DCSection>

        {/* ────────────────────────────────────────────────────────── */}
        {/* ④ iPadOS — mirrors web desktop                                */}
        {/* ────────────────────────────────────────────────────────── */}
        <DCSection id="app-ipad" title="④ iPadOS · Editorial flow" subtitle="Same screens as Web Desktop, in a landscape iPad bezel. Same sidebar shell — typical for the analysis + monthly review surface on a tablet.">
          <DCArtboard id="ipad-accts"     label="Accounts · overview"   width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebAccountsOverview th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="ipad-acct-d"    label="Account · detail"      width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebAccountDetail th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="ipad-budgets"   label="Budgets · overview"    width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebBudgetsOverview th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="ipad-budget-d"  label="Budget · detail"       width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebBudgetDetail th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="ipad-sched"     label="Scheduled · calendar"  width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebScheduledOverview th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="ipad-insights"  label="Insights · analytics"  width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebInsightsOverview th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="ipad-activity"  label="Activity · optional"   width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebActivityOverview th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="ipad-goals"     label="Goals · optional"      width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebGoalsOverview th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="ipad-subs"      label="Subscriptions · optional" width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebSubscriptionsOverview th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="ipad-txd"       label="Transaction detail"    width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebTxDetail th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="ipad-settings"  label="Settings"              width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebSettings th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="ipad-tabs"      label="Settings → Tab layout" width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebTabLayoutPage th={th}/></IPadFrame></DCArtboard>
        </DCSection>

        {/* ────────────────────────────────────────────────────────── */}
        {/* ⑤ Ledger schema · NEW screens for the v2.0 backend          */}
        {/* ────────────────────────────────────────────────────────── */}
        <DCSection id="schema-intro" title="⑤ Ledger schema · v2.0 backend" subtitle="Screens added for the SQLite backend redesign: multi-ledger isolation, transfer_groups with locked FX, the pending-review queue, counterparties with aliases, recurring templates + splits, and the FX/sync admin. Each surface references its underlying table.">
          <DCArtboard id="schema-brief" label="What's new" width={620} height={520}>
            <SchemaBriefCard th={th}/>
          </DCArtboard>
          <DCArtboard id="schema-map" label="Schema → screen map" width={540} height={520}>
            <SchemaMapCard th={th}/>
          </DCArtboard>
        </DCSection>

        <DCSection id="schema-mobile" title="⑤·a Web Mobile · ledger schema screens" subtitle="Browser-frame views — mobile width. Each surfaces a part of the v2 schema.">
          <DCArtboard id="sm-ledger"   label="Ledger switcher · sheet"     width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/ledgers/switch"><ScreenLedgerSwitch th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="sm-pending"  label="Pending review · status='pending'" width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/pending"><ScreenPendingReview th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="sm-xfer"     label="Transfer detail · transfer_groups" width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/transfers/tg-002"><ScreenTransferDetail th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="sm-cp"       label="Counterparties · aliases" width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/merchants"><ScreenCounterparties th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="sm-rt"       label="Recurring template · splits" width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/recurring/rt-salary"><ScreenRecurringTemplate th={th}/></MobileWebFrame></DCArtboard>
          <DCArtboard id="sm-fx"       label="Multi-currency txn · amount_base locked" width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}><MobileWebFrame url="finch.app/tx/t-jpy-001"><ScreenFxTransaction th={th}/></MobileWebFrame></DCArtboard>
        </DCSection>

        <DCSection id="schema-ios" title="⑤·b iOS native · ledger schema screens" subtitle="Same screens, native iOS bezel.">
          <DCArtboard id="si-ledger"   label="Ledger switcher · sheet"           width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenLedgerSwitch th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="si-pending"  label="Pending review"                    width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenPendingReview th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="si-xfer"     label="Transfer detail · locked FX"       width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenTransferDetail th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="si-cp"       label="Counterparties"                    width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenCounterparties th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="si-rt"       label="Recurring · salary w/ splits"      width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenRecurringTemplate th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="si-fx"       label="JPY txn · amount + amount_base"    width={PHONE_W} height={PHONE_H}><PhoneFrame><ScreenFxTransaction th={th}/></PhoneFrame></DCArtboard>
        </DCSection>

        <DCSection id="schema-desktop" title="⑤·c Web Desktop · ledger schema admin" subtitle="Larger admin and management surfaces. Each page is wrapped in the same sidebar shell.">
          <DCArtboard id="sd-ledgers" label="Ledger admin · isolated books"      width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/ledgers"><WebLedgerAdmin th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="sd-pending" label="Pending review · queue"             width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/pending"><WebPendingReview th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="sd-cp"      label="Counterparties · match logic"       width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/merchants"><WebCounterparties th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="sd-rt"      label="Recurring templates · with splits"  width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/recurring"><WebRecurringTemplates th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="sd-cats"    label="Category hierarchy"                 width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/categories"><WebCategoryTree th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="sd-admin"   label="System · rates + sync_log"          width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/system"><WebAdminPanel th={th}/></WebFrame></DCArtboard>
        </DCSection>

        <DCSection id="schema-ipad" title="⑤·d iPadOS · ledger schema admin" subtitle="Same admin surfaces in a landscape iPad bezel.">
          <DCArtboard id="sp-ledgers" label="Ledger admin"        width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebLedgerAdmin th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="sp-pending" label="Pending review"      width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebPendingReview th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="sp-cp"      label="Counterparties"      width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebCounterparties th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="sp-rt"      label="Recurring templates" width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebRecurringTemplates th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="sp-cats"    label="Category hierarchy"  width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebCategoryTree th={th}/></IPadFrame></DCArtboard>
          <DCArtboard id="sp-admin"   label="System admin"        width={IPAD_INNER_W + 56} height={IPAD_INNER_H + 112}><IPadFrame><WebAdminPanel th={th}/></IPadFrame></DCArtboard>
        </DCSection>

        {/* ────────────────────────────────────────────────────────── */}
        {/* R · Variations · for reference                               */}
        {/* ────────────────────────────────────────────────────────── */}
        <DCSection id="ref-mobile-dashboards" title="Reference · Mobile dashboard variations" subtitle="Six early visual explorations. Kept here for reference — the chosen Editorial direction lives in section ①.">
          <DCArtboard id="ref-m-editorial" label="01 · Editorial"     width={PHONE_W} height={PHONE_H}><PhoneFrame><DashEditorial th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ref-m-mono"      label="02 · Minimal mono"  width={PHONE_W} height={PHONE_H}><PhoneFrame><DashMono th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ref-m-donut"     label="03 · Donut hero"    width={PHONE_W} height={PHONE_H}><PhoneFrame><DashDonut th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ref-m-calendar"  label="04 · Calendar"      width={PHONE_W} height={PHONE_H}><PhoneFrame><DashCalendar th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ref-m-stacked"   label="05 · Stacked bars"  width={PHONE_W} height={PHONE_H}><PhoneFrame><DashStacked th={th}/></PhoneFrame></DCArtboard>
          <DCArtboard id="ref-m-stream"    label="06 · Stream"        width={PHONE_W} height={PHONE_H}><PhoneFrame><DashStream th={th}/></PhoneFrame></DCArtboard>
        </DCSection>

        <DCSection id="ref-web-dashboards" title="Reference · Web dashboard variations" subtitle="Six early desktop explorations. The Classic-admin sidebar pattern from #02 was selected as the chrome for the Editorial desktop flow.">
          <DCArtboard id="ref-w-editorial"   label="01 · Editorial newspaper" width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/dashboard"><WebEditorial th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="ref-w-classic"     label="02 · Classic admin ★"     width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/dashboard"><WebClassic th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="ref-w-spreadsheet" label="03 · Spreadsheet"          width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/activity"><WebSpreadsheet th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="ref-w-magazine"    label="04 · Magazine"             width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/report"><WebMagazine th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="ref-w-timeline"    label="05 · Timeline"             width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/activity"><WebTimeline th={th}/></WebFrame></DCArtboard>
          <DCArtboard id="ref-w-insights"    label="06 · Insights-first"       width={WEB_W} height={WEB_H + 88}><WebFrame url="finch.app/insights"><WebInsights th={th}/></WebFrame></DCArtboard>
        </DCSection>
      </DesignCanvas>

      {/* Tweaks panel */}
      <TweaksPanel title="Tweaks">
        <TweakSection label="Theme"/>
        <TweakColor label="Palette" value={t.palette}
          options={[
            ['#f5f1ea','#1a1614','#c96442'],
            ['#0e0d0c','#f1ece2','#e07856'],
            ['#f3f0e8','#1a2018','#3d6b46'],
            ['#f4f4f8','#0f1024','#3a3aff'],
          ]}
          onChange={(v) => {
            const idx = [['#f5f1ea','#1a1614','#c96442'],['#0e0d0c','#f1ece2','#e07856'],['#f3f0e8','#1a2018','#3d6b46'],['#f4f4f8','#0f1024','#3a3aff']]
              .findIndex(p => p[0] === v[0]);
            const ids = ['warm','noir','forest','indigo'];
            setTweak('palette', ids[idx] || 'warm');
          }}
        />
        <TweakSelect label="Font pairing" value={t.fonts}
          options={[
            { value: 'editorial', label: 'Editorial · Instrument + Inter' },
            { value: 'grotesk',   label: 'Grotesk · Space Grotesk' },
            { value: 'classic',   label: 'Classic · Inter only' },
            { value: 'swiss',     label: 'Swiss · Inter Tight' },
          ]}
          onChange={(v) => setTweak('fonts', v)}
        />

        <TweakSection label="Layout"/>
        <TweakRadio label="Density" value={t.density} options={['compact','regular','roomy']}
          onChange={(v) => setTweak('density', v)}/>

        <TweakSection label="Locale"/>
        <TweakRadio label="Currency" value={t.currency} options={['USD','EUR','GBP','JPY']}
          onChange={(v) => setTweak('currency', v)}/>

        <TweakSection label="Notes"/>
        <div style={{ fontSize: 11, lineHeight: 1.5, color: 'rgba(41,38,27,0.7)', padding: '4px 2px' }}>
          Editorial flow is the main product, shown across <b>three platforms</b>. Six dashboard variations are kept at the bottom for reference.
        </div>
      </TweaksPanel>
    </>
  );
}

// ─────────────────────────────────────────────────────────────
// Frames
// ─────────────────────────────────────────────────────────────
function PhoneFrame({ children }) {
  return (
    <div style={{ width: PHONE_W, height: PHONE_H, position: 'relative' }}>
      <IOSDevice width={PHONE_W} height={PHONE_H}>{children}</IOSDevice>
    </div>
  );
}

function WebFrame({ url, children }) {
  return (
    <ChromeWindow tabs={[{ title: 'Finch · Money for grown-ups' }]} url={url} width={WEB_W} height={WEB_H + 88}>
      {children}
    </ChromeWindow>
  );
}

// Mobile browser frame — narrow Chrome window wrapping mobile screen content.
// The same iOS screen components render inside (their built-in top padding
// reads as comfortable whitespace under the URL bar — no iOS status bar here).
function MobileWebFrame({ url, children }) {
  return (
    <ChromeWindow tabs={[{ title: 'Finch' }]} url={url} width={WEB_MOBILE_W} height={WEB_MOBILE_H + 88}>
      <div style={{ width: '100%', height: '100%', overflow: 'hidden', position: 'relative' }}>
        {children}
      </div>
    </ChromeWindow>
  );
}

// iPad landscape frame — bezel + status bar + home indicator. Content fills
// the inner display area at iPad resolution; the desktop WebShell flexes
// naturally to fit.
function IPadFrame({ children }) {
  return (
    <IPadDevice>
      <div style={{ width: '100%', height: '100%' }}>{children}</div>
    </IPadDevice>
  );
}

// ─────────────────────────────────────────────────────────────
// System overview card — quick reference of who/what/why
// ─────────────────────────────────────────────────────────────
function SystemOverview({ th }) {
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, padding: 32, fontFamily: th.body, display: 'flex', flexDirection: 'column' }}>
      <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, marginBottom: 14 }}>FINCH · DESIGN BRIEF</div>
      <div style={{ fontFamily: th.display, fontSize: 44, lineHeight: 1, letterSpacing: -1.3, marginBottom: 14 }}>
        Money for grown-ups.
      </div>
      <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 17, color: th.ink2, lineHeight: 1.4, marginBottom: 20 }}>
        An expense tracker that treats finance like a story you're already living — quiet typography, honest numbers, no dashboards that yell.
      </div>
      <div style={{ height: 1, background: th.line, margin: '4px 0 18px' }}/>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 18, fontSize: 12.5, color: th.ink2, lineHeight: 1.5 }}>
        <div>
          <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1.2, marginBottom: 4 }}>WHO</div>
          Individuals managing personal finances — one earner, multiple accounts, modest savings goals.
        </div>
        <div>
          <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1.2, marginBottom: 4 }}>WHERE</div>
          Mobile-first (iOS + web mobile) for capture & glance, web desktop for analysis & monthly review.
        </div>
        <div>
          <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1.2, marginBottom: 4 }}>NAV</div>
          5 mobile tabs: Accounts · Budgets · [+] · Scheduled · Insights. Settings lives behind the profile chip.
        </div>
        <div>
          <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1.2, marginBottom: 4 }}>HOW</div>
          Quiet warm-cream palette, mixed serif display + clean UI sans, tabular numerics everywhere money lives.
        </div>
      </div>

      <div style={{ flex: 1 }}/>

      <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 16 }}>
        <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1, marginBottom: 8 }}>SECTIONS IN THIS CANVAS</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6, fontSize: 13 }}>
          {[
            ['① Web Mobile',     'Primary · 13 screens'],
            ['② Web Desktop',    'Primary · 12 screens'],
            ['③ iOS native',     'Mirrors Web Mobile'],
            ['④ iPadOS',         'Mirrors Web Desktop'],
            ['Reference · Mobile', '6 dashboard variations'],
            ['Reference · Desktop','6 layout variations'],
          ].map(([l, r]) => (
            <div key={l} style={{ display: 'flex', justifyContent: 'space-between', borderBottom: `0.5px dotted ${th.line}`, paddingBottom: 4 }}>
              <span style={{ fontWeight: 500 }}>{l}</span>
              <span style={{ color: th.muted }}>{r}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// Palette card — current palette swatches + type pairing preview
function PaletteCard({ th }) {
  const pal = PALETTES[Object.keys(PALETTES).find(k => PALETTES[k].paper === th.paper)] || PALETTES.warm;
  const swatches = [
    { key: 'paper', label: 'Paper · bg' },
    { key: 'card', label: 'Card' },
    { key: 'ink', label: 'Ink · text' },
    { key: 'muted', label: 'Muted' },
    { key: 'accent', label: 'Accent' },
    { key: 'pos', label: 'Positive' },
    { key: 'neg', label: 'Negative' },
    { key: 'warn', label: 'Warning' },
  ];
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, padding: 28, fontFamily: th.body, display: 'flex', flexDirection: 'column' }}>
      <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, marginBottom: 10 }}>SYSTEM · PALETTE</div>
      <div style={{ fontFamily: th.display, fontSize: 30, letterSpacing: -0.6, marginBottom: 4 }}>{pal.name}</div>
      <div style={{ fontSize: 12, color: th.muted, marginBottom: 22 }}>Live — change in Tweaks panel</div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, marginBottom: 22 }}>
        {swatches.map((s) => (
          <div key={s.key} style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
            <div style={{ width: 40, height: 40, borderRadius: 8, background: th[s.key], border: `1px solid ${th.line}` }}/>
            <div>
              <div style={{ fontSize: 12, fontWeight: 500 }}>{s.label}</div>
              <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.3 }}>{th[s.key]}</div>
            </div>
          </div>
        ))}
      </div>

      <div style={{ height: 1, background: th.line, marginBottom: 16 }}/>

      <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1, marginBottom: 10 }}>TYPE PAIRING</div>
      <div style={{ fontFamily: th.display, fontSize: 38, letterSpacing: -1, lineHeight: 1, marginBottom: 4 }}>Finch</div>
      <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 18, color: th.muted, marginBottom: 16 }}>Display · for moments</div>
      <div style={{ fontSize: 14, lineHeight: 1.5, color: th.ink2 }}>The body sans is set in <b>{th.body.split(',')[0].replace(/'/g, '')}</b>. Numbers use tabular figures so the dollar columns line up exactly when you scan.</div>

      <div style={{ flex: 1 }}/>
      <div style={{ marginTop: 18, fontFamily: th.mono, fontSize: 11, color: th.muted }}>
        Money: <Money value={1234.56} currency={th.currency} style={{ color: th.ink, fontWeight: 500 }}/> · <Money value={-99.01} currency={th.currency} style={{ color: th.neg }}/>
      </div>
    </div>
  );
}

// Components card — the building blocks used across screens
function ComponentsCard({ th }) {
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, padding: 26, fontFamily: th.body, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, marginBottom: 10 }}>SYSTEM · COMPONENTS</div>
      <div style={{ fontFamily: th.display, fontSize: 26, letterSpacing: -0.5, marginBottom: 18 }}>Building blocks</div>

      <div style={{ marginBottom: 14 }}>
        <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1, marginBottom: 6 }}>MONEY</div>
        <div style={{ display: 'flex', gap: 14, alignItems: 'baseline' }}>
          <span style={{ fontFamily: th.display, fontSize: 36, letterSpacing: -1 }}><Money value={MOCK.balance} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/></span>
          <Money value={1234.56} currency={th.currency} style={{ fontSize: 18 }}/>
          <Money value={-12.34} currency={th.currency} style={{ fontSize: 14, color: th.neg }}/>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, marginBottom: 14 }}>
        <div style={{ padding: 12, background: th.card, border: `1px solid ${th.line}`, borderRadius: 10 }}>
          <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1, marginBottom: 6 }}>SPARKLINE</div>
          <Sparkline values={MOCK.daily.slice(-14)} width={170} height={36} color={th.accent}/>
        </div>
        <div style={{ padding: 12, background: th.card, border: `1px solid ${th.line}`, borderRadius: 10 }}>
          <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1, marginBottom: 6 }}>BARS</div>
          <BarChart values={MOCK.monthly.slice(-6).map(m => m.v)} labels={MOCK.monthly.slice(-6).map(m => m.m[0])} width={170} height={36} color={th.muted} highlight={th.accent} muted={th.paperAlt}/>
        </div>
        <div style={{ padding: 12, background: th.card, border: `1px solid ${th.line}`, borderRadius: 10, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Donut slices={MOCK.categories.slice(0,5).map(c => ({ value: c.spent, color: `oklch(0.65 0.13 ${c.hue})` }))} size={70} stroke={10}/>
        </div>
        <div style={{ padding: 12, background: th.card, border: `1px solid ${th.line}`, borderRadius: 10 }}>
          <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1, marginBottom: 6 }}>STACKED</div>
          <StackedBar slices={MOCK.categories.slice(0,5).map(c => ({ value: c.spent, color: `oklch(0.65 0.13 ${c.hue})` }))} width={170} height={8} radius={4}/>
        </div>
      </div>

      <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1, marginBottom: 6 }}>BUTTONS</div>
      <div style={{ display: 'flex', gap: 8, marginBottom: 14 }}>
        <div style={{ height: 32, padding: '0 14px', background: th.ink, color: th.paper, borderRadius: 16, display: 'flex', alignItems: 'center', fontSize: 12, fontWeight: 500 }}>Primary</div>
        <div style={{ height: 32, padding: '0 14px', background: th.accent, color: '#fff', borderRadius: 16, display: 'flex', alignItems: 'center', fontSize: 12, fontWeight: 500 }}>Accent</div>
        <div style={{ height: 32, padding: '0 14px', border: `1px solid ${th.line}`, color: th.ink, borderRadius: 16, display: 'flex', alignItems: 'center', fontSize: 12, fontWeight: 500 }}>Outline</div>
        <div style={{ height: 32, padding: '0 14px', background: th.paperAlt, color: th.ink, borderRadius: 16, display: 'flex', alignItems: 'center', fontSize: 12, fontWeight: 500 }}>Soft</div>
      </div>

      <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1, marginBottom: 6 }}>MERCHANTS · CATEGORIES</div>
      <div style={{ display: 'flex', gap: 8 }}>
        {MOCK.categories.slice(0, 6).map((c) => (
          <div key={c.id} style={{ width: 32, height: 32, borderRadius: 16, background: `oklch(0.92 0.04 ${c.hue})`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}>
            <Icon name={c.icon} size={14}/>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Ledger schema · intro cards
// ─────────────────────────────────────────────────────────────
function SchemaBriefCard({ th }) {
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, padding: 32, fontFamily: th.body, display: 'flex', flexDirection: 'column' }}>
      <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, marginBottom: 14 }}>BACKEND · v2.0 SQLite</div>
      <div style={{ fontFamily: th.display, fontSize: 44, lineHeight: 1, letterSpacing: -1.3, marginBottom: 14 }}>
        New shape, new screens.
      </div>
      <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 17, color: th.ink2, lineHeight: 1.4, marginBottom: 20 }}>
        Six concepts the v2 schema introduces — and the surfaces that make them legible to a human.
      </div>
      <div style={{ height: 1, background: th.line, margin: '4px 0 18px' }}/>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 14, fontSize: 13, color: th.ink2, lineHeight: 1.5 }}>
        {[
          ['Ledgers',           'Isolated books. Personal · Family · Side studio · Travel. Data never crosses.'],
          ['Multi-currency',    'Every txn stores amount + amount_base, with exchange_rate locked at import.'],
          ['Transfer groups',   'Two transactions share one transfer_group_id — same-ledger and cross-ledger.'],
          ['Pending review',    'status = pending hides from reports until you confirm. Two sources: recurring + import.'],
          ['Counterparties',    '7-Eleven, 7-11, SEVEN ELEVEN → one canonical name. Aliases live as JSON.'],
          ['Recurring + splits','Salary of $5,800 → 60/25/15 across three accounts. amount_pct or amount_abs, never both.'],
        ].map(([k, v], i) => (
          <div key={k} style={{ display: 'grid', gridTemplateColumns: '160px 1fr', gap: 14, paddingBottom: 12, borderBottom: i < 5 ? `0.5px dotted ${th.line}` : 'none' }}>
            <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic', color: th.ink, letterSpacing: -0.2 }}>{k}</div>
            <div>{v}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

function SchemaMapCard({ th }) {
  const rows = [
    ['ledgers',                'Ledger switcher · admin'],
    ['accounts + groups',      'Accounts (existing) · group net-worth toggle'],
    ['categories',             'Category tree (parent + sub)'],
    ['transactions',           'Activity (existing)'],
    ['  + amount/amount_base', 'Multi-currency txn detail'],
    ['  + status = pending',   'Pending review queue'],
    ['  + transfer_group_id',  'Transfer detail'],
    ['transfer_groups',        'Transfer detail · locked FX panel'],
    ['counterparties',         'Merchants page · alias chips'],
    ['recurring_templates',    'Templates list (desktop) · template detail (mobile)'],
    ['recurring_splits',       'Splits panel inside template detail'],
    ['budgets',                'Budgets (existing) · filters · rollover'],
    ['exchange_rates',         'System admin · rate book table + trend'],
    ['sync_log',               'System admin · devices reading this ledger'],
    ['ledger_summaries',       'Reports (existing, fed by triggers)'],
  ];
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, padding: 32, fontFamily: th.body, display: 'flex', flexDirection: 'column' }}>
      <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, marginBottom: 14 }}>SCHEMA → SCREEN MAP</div>
      <div style={{ fontFamily: th.display, fontSize: 32, lineHeight: 1, letterSpacing: -0.8, marginBottom: 18 }}>
        <i>Each table</i> earns at least one surface.
      </div>
      <div style={{ fontSize: 12.5, color: th.ink2, lineHeight: 1.4, marginBottom: 16 }}>
        Existing Finch screens already cover most of the schema. The new ⑤ section adds the surfaces that didn't exist yet.
      </div>

      <div style={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        {rows.map(([col, screen], i) => (
          <div key={i} style={{ display: 'grid', gridTemplateColumns: '1.1fr 1.4fr', gap: 12, padding: '7px 0', borderTop: i ? `0.5px dotted ${th.line}` : 'none', alignItems: 'baseline' }}>
            <div style={{ fontFamily: th.mono, fontSize: 11, color: col.startsWith('  ') ? th.muted : th.ink2, letterSpacing: 0.2 }}>{col}</div>
            <div style={{ fontSize: 12.5, color: th.ink }}>{screen}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

// Mount
const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App/>);
