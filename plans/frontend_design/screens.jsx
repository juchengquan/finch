// Eight mobile screens in the chosen "Editorial" direction.
// 390 wide.

// Shared header — slot-based.
// Default layout: profile chip (left) / centered italic title / search (right).
// Use `back={true}` to swap the profile for a back chevron (drill-in/modal).
// Pass `leading` to override the left slot, `trailing` to override the right.
function ScreenHeader({ th, title, back = false, leading, trailing }) {
  const _leading = leading !== undefined ? leading : (back
    ? <div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="chev-l" size={16}/></div>
    : <ProfileChip th={th}/>);
  const _trailing = trailing !== undefined ? trailing : <div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="search" size={16}/></div>;
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1fr auto 1fr', alignItems: 'center', padding: '0 20px', marginBottom: 18, gap: 8 }}>
      <div style={{ justifySelf: 'start', minHeight: 36 }}>{_leading}</div>
      <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic', letterSpacing: -0.2, textAlign: 'center' }}>{title}</div>
      <div style={{ justifySelf: 'end', display: 'flex', alignItems: 'center', gap: 8, minHeight: 36 }}>{_trailing}</div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Screen · Add Expense
// ─────────────────────────────────────────────────────────────
function ScreenAddExpense({ th }) {
  const [amount] = React.useState('42.18');
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ paddingTop: STATUS_PAD + 8 }}>
        <ScreenHeader th={th} title="New expense" leading={null} trailing={<div style={{ width: 32, height: 32, borderRadius: 16, background: th.paperAlt, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="x" size={16}/></div>}/>
      </div>

      {/* Hero amount */}
      <div style={{ padding: '20px 24px 32px', textAlign: 'center' }}>
        <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, marginBottom: 14 }}>AMOUNT</div>
        <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'center', gap: 6 }}>
          <span style={{ fontFamily: th.display, fontSize: 32, color: th.muted, alignSelf: 'flex-start', marginTop: 18 }}>$</span>
          <span style={{ fontFamily: th.display, fontSize: 84, lineHeight: 1, letterSpacing: -3, fontWeight: 400 }}>
            {amount.split('.')[0]}
          </span>
          <span style={{ fontFamily: th.display, fontSize: 40, color: th.muted }}>.{amount.split('.')[1]}</span>
        </div>
        <div style={{ marginTop: 16, display: 'flex', justifyContent: 'center', gap: 8 }}>
          {['Coffee · $6', 'Lunch · $14', 'Uber · $18'].map((s) => (
            <div key={s} style={{ height: 26, padding: '0 10px', display: 'flex', alignItems: 'center', borderRadius: 13, border: `1px solid ${th.line}`, fontSize: 11, color: th.muted }}>{s}</div>
          ))}
        </div>
      </div>

      {/* Form fields */}
      <div style={{ padding: '0 20px' }}>
        {[
          { label: 'Merchant', value: 'Trader Joe\u2019s',  icon: 'tag',    inline: <span style={{ color: th.accent, fontSize: 11, fontWeight: 500 }}>· auto-detected</span> },
          { label: 'Category', value: 'Food & Dining',      icon: 'fork',   chev: true },
          { label: 'Account',  value: 'Amex Gold · 1009',   icon: 'wallet', chev: true },
          { label: 'Date',     value: 'Today · Sat May 24', icon: 'calendar', chev: true },
          { label: 'Note',     value: 'Weekly groceries',   icon: 'edit',   placeholder: false },
        ].map((f, i) => (
          <div key={f.label} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 0', borderBottom: `1px solid ${th.line}` }}>
            <div style={{ width: 32, height: 32, borderRadius: 16, background: th.paperAlt, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink2, flexShrink: 0 }}><Icon name={f.icon} size={15}/></div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 11, color: th.muted, letterSpacing: 0.4, textTransform: 'uppercase' }}>{f.label}</div>
              <div style={{ fontSize: 15, marginTop: 1, display: 'flex', alignItems: 'baseline', gap: 6 }}>
                {f.value}{f.inline}
              </div>
            </div>
            {f.chev && <Icon name="chev" size={14} style={{ color: th.muted }}/>}
          </div>
        ))}
        {/* Receipt drop */}
        <div style={{ display: 'flex', gap: 10, marginTop: 16 }}>
          <div style={{ flex: 1, height: 56, borderRadius: 12, border: `1px dashed ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, fontSize: 12, color: th.muted }}>
            <Icon name="cam" size={16}/>Attach receipt
          </div>
          <div style={{ width: 56, height: 56, borderRadius: 12, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.muted }}><Icon name="split" size={18}/></div>
        </div>
      </div>

      {/* Save button */}
      <div style={{ position: 'absolute', bottom: 32, left: 20, right: 20 }}>
        <div style={{ height: 54, borderRadius: 27, background: th.ink, color: th.paper, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 16, fontWeight: 500, letterSpacing: -0.2 }}>
          Save expense · <Money value={42.18} currency={th.currency} style={{ marginLeft: 6, opacity: 0.7 }}/>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Screen · Transactions List (full)
// ─────────────────────────────────────────────────────────────
function ScreenTransactions({ th }) {
  const groups = {};
  MOCK.transactions.forEach((tx) => { (groups[tx.date] = groups[tx.date] || []).push(tx); });
  const dates = Object.keys(groups).sort().reverse();
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ paddingTop: STATUS_PAD + 8 }}>
        <ScreenHeader th={th} title="Activity" back={false} trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="filter" size={16}/></div>}/>
      </div>

      <div style={{ height: 'calc(100% - 100px)', overflowY: 'auto', paddingBottom: 110 }}>
        {/* Sub-summary */}
        <div style={{ padding: '0 20px 16px', display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
          <div>
            <div style={{ fontFamily: th.display, fontSize: 30, letterSpacing: -0.8, lineHeight: 1 }}>{fmtMoneyShort(MOCK.monthSpent, th.currency)}</div>
            <div style={{ fontSize: 11, color: th.muted, marginTop: 4 }}>May · 16 transactions</div>
          </div>
          <div style={{ display: 'flex', gap: 6 }}>
            {['All','Out','In'].map((t, i) => (
              <div key={t} style={{ padding: '6px 12px', borderRadius: 6, fontSize: 11, fontWeight: 500, background: i === 0 ? th.ink : 'transparent', color: i === 0 ? th.paper : th.muted, border: i === 0 ? 'none' : `1px solid ${th.line}` }}>{t}</div>
            ))}
          </div>
        </div>

        {/* Search */}
        <div style={{ margin: '0 20px 18px', height: 38, borderRadius: 19, background: th.paperAlt, display: 'flex', alignItems: 'center', gap: 10, padding: '0 14px', color: th.muted, fontSize: 13 }}>
          <Icon name="search" size={14}/>Search merchants, categories…
          <Icon name="mic" size={14} style={{ marginLeft: 'auto' }}/>
        </div>

        {dates.slice(0, 5).map((d) => {
          const dayTotal = groups[d].reduce((s, t) => s + t.amount, 0);
          const dayLabel = d === '2026-05-24' ? 'Today' : d === '2026-05-23' ? 'Yesterday' : new Date(d).toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' });
          return (
            <div key={d} style={{ marginBottom: 6 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', padding: '8px 20px', fontFamily: th.mono, fontSize: 10, letterSpacing: 1.2, color: th.muted, textTransform: 'uppercase' }}>
                <span>{dayLabel.toUpperCase()}</span>
                <span>{dayTotal > 0 ? '+' : ''}{fmtMoneyShort(dayTotal, th.currency)}</span>
              </div>
              <div style={{ background: th.card, marginBottom: 4 }}>
                {groups[d].map((tx, i) => {
                  const cat = catById(tx.category);
                  const inc = tx.amount > 0;
                  return (
                    <div key={tx.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 20px', borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
                      <MerchantGlyph name={tx.merchant} size={36} hue={cat.hue}/>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontSize: 14, fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{tx.merchant}</div>
                        <div style={{ fontSize: 11, color: th.muted, marginTop: 2, display: 'flex', alignItems: 'center', gap: 6 }}>
                          <CatDot hue={cat.hue}/>{cat.name || 'Income'}
                          {tx.pending && <span style={{ color: th.warn }}>· pending</span>}
                        </div>
                      </div>
                      <div style={{ fontSize: 14, fontWeight: 500, color: inc ? th.pos : th.ink, fontVariantNumeric: 'tabular-nums' }}>
                        {inc ? '+' : ''}{fmtMoney(tx.amount, th.currency)}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>
      <MobileTabBar th={th} active="insights"/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Screen · Transaction Detail
// ─────────────────────────────────────────────────────────────
function ScreenTxDetail({ th }) {
  const tx = MOCK.transactions[1]; // Whole Foods
  const cat = catById(tx.category);
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ paddingTop: STATUS_PAD + 8 }}>
        <ScreenHeader th={th} title="" back={true} trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="dots" size={16}/></div>}/>
      </div>

      {/* Hero */}
      <div style={{ padding: '0 24px 28px', textAlign: 'center' }}>
        <MerchantGlyph name={tx.merchant} size={64} hue={cat.hue}/>
        <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 22, color: th.muted, marginTop: 18 }}>You spent at</div>
        <div style={{ fontFamily: th.display, fontSize: 34, letterSpacing: -0.8, lineHeight: 1, marginTop: 4 }}>{tx.merchant}</div>
        <div style={{ fontFamily: th.display, fontSize: 56, letterSpacing: -2, marginTop: 18, fontWeight: 400 }}>
          <Money value={tx.amount} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
        </div>
        <div style={{ fontSize: 12, color: th.muted, marginTop: 6 }}>Fri, May 23 · 6:42 PM · {acctById(tx.account).name}</div>
      </div>

      {/* Action bar */}
      <div style={{ padding: '0 20px 22px', display: 'flex', gap: 8 }}>
        {[
          { i: 'split',  l: 'Split' },
          { i: 'tag',    l: 'Recategorize' },
          { i: 'sync',   l: 'Recurring' },
          { i: 'cam',    l: 'Receipt' },
        ].map((a) => (
          <div key={a.l} style={{ flex: 1, height: 60, borderRadius: 12, border: `1px solid ${th.line}`, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 4, color: th.ink }}>
            <Icon name={a.i} size={18}/>
            <span style={{ fontSize: 10, fontWeight: 500 }}>{a.l}</span>
          </div>
        ))}
      </div>

      {/* Details */}
      <div style={{ padding: '0 20px' }}>
        <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: '4px 16px' }}>
          {[
            { l: 'Category',    v: <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}><CatDot hue={cat.hue}/>{cat.name}</span> },
            { l: 'Account',     v: 'Amex Gold · 1009' },
            { l: 'Status',      v: 'Posted' },
            { l: 'Note',        v: tx.note },
            { l: 'Transaction', v: 'AMX-9F2B-44A1' },
          ].map((r, i) => (
            <div key={r.l} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px 0', borderTop: i ? `0.5px solid ${th.line}` : 'none', fontSize: 13 }}>
              <span style={{ color: th.muted }}>{r.l}</span>
              <span>{r.v}</span>
            </div>
          ))}
        </div>

        {/* Mini context */}
        <div style={{ marginTop: 18, padding: 16, background: th.card, border: `1px solid ${th.line}`, borderRadius: 14 }}>
          <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.2, color: th.muted, marginBottom: 10 }}>YOUR HISTORY HERE</div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 14 }}>
            <div style={{ fontSize: 13 }}>4 visits in May</div>
            <div style={{ fontFamily: th.display, fontSize: 22, letterSpacing: -0.4 }}><Money value={184.62} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/></div>
          </div>
          <BarChart values={[42, 38, 84, 21]} labels={['M3','M10','M17','M23']} width={310} height={50} color={th.muted} highlight={th.accent} muted={th.paperAlt}/>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Screen · Insights
// ─────────────────────────────────────────────────────────────
function ScreenInsights({ th }) {
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <div style={{ paddingTop: STATUS_PAD + 8 }}>
          <ScreenHeader th={th} title="Insights" back={false} trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="calendar" size={16}/></div>}/>
        </div>

        <div style={{ padding: '0 20px' }}>
          {/* Hero metric */}
          <div style={{ borderTop: `1px solid ${th.line}`, paddingTop: 18, marginBottom: 22 }}>
            <div style={{ fontSize: 10, color: th.muted, letterSpacing: 1.2, textTransform: 'uppercase' }}>You're spending less</div>
            <div style={{ fontFamily: th.display, fontSize: 60, letterSpacing: -2, lineHeight: 1, marginTop: 6 }}>↓ 8.4%</div>
            <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 16, color: th.ink2, marginTop: 6 }}>
              than April. Mostly less <span style={{ color: th.accent }}>Shopping</span>.
            </div>
          </div>

          {/* 12-month bar chart */}
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 18, marginBottom: 16 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 12 }}>
              <div style={{ fontSize: 13, fontWeight: 600 }}>Monthly spending</div>
              <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.8 }}>LAST 12 MO</div>
            </div>
            <BarChart values={MOCK.monthly.map(m => m.v)} labels={MOCK.monthly.map(m => m.m[0])} width={310} height={120} color={th.muted} highlight={th.accent} muted={th.paperAlt}/>
          </div>

          {/* Insight cards */}
          {[
            { tone: 'pos',  icon: 'arrow-d', title: 'Entertainment cut by 71%', body: 'From $342 last month to $98 this month. You\u2019ve eaten out 6 fewer times.' },
            { tone: 'warn', icon: 'arrow-u', title: 'Shopping over budget',     body: 'At $312 of $300 with 7 days left. Pause for now?' },
            { tone: 'neut', icon: 'sparkle', title: 'Fridays are spendy days',  body: 'You spend 2.3× more on Fridays. Mostly food & drinks.' },
          ].map((ins) => {
            const c = ins.tone === 'pos' ? th.pos : ins.tone === 'warn' ? th.warn : th.accent;
            return (
              <div key={ins.title} style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 16, marginBottom: 10, display: 'flex', gap: 12 }}>
                <div style={{ width: 32, height: 32, borderRadius: 16, background: `${c}1a`, color: c, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><Icon name={ins.icon} size={16}/></div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontFamily: th.display, fontSize: 18, letterSpacing: -0.2, marginBottom: 4 }}>{ins.title}</div>
                  <div style={{ fontSize: 12, color: th.ink2, lineHeight: 1.45 }}>{ins.body}</div>
                </div>
              </div>
            );
          })}

          {/* Compare strip */}
          <div style={{ marginTop: 22 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 10 }}>
              <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic' }}>Apr vs May</div>
              <span style={{ fontSize: 11, color: th.muted }}>Top changes</span>
            </div>
            {[
              { name: 'Entertainment', a: 342, b: 98, d: -71 },
              { name: 'Shopping',      a: 218, b: 312, d: 43 },
              { name: 'Food & Dining', a: 720, b: 612, d: -15 },
              { name: 'Transport',     a: 196, b: 184, d: -6 },
            ].map((c, i) => (
              <div key={c.name} style={{ display: 'flex', alignItems: 'center', padding: '12px 0', borderTop: `1px solid ${th.line}` }}>
                <div style={{ flex: 1, fontSize: 14 }}>{c.name}</div>
                <div style={{ fontFamily: th.mono, fontSize: 11, color: th.muted, marginRight: 14 }}>
                  {fmtMoneyShort(c.a, th.currency)} → {fmtMoneyShort(c.b, th.currency)}
                </div>
                <div style={{ fontFamily: th.mono, fontSize: 12, fontWeight: 600, color: c.d < 0 ? th.pos : th.neg }}>
                  {c.d > 0 ? '+' : ''}{c.d}%
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
      <MobileTabBar th={th} active="insights"/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Screen · Accounts (the home in the Editorial flow)
// Accounts are grouped (Cash & Banking · Credit · Investments) under
// collapsible section headers. Each row is a slim, tappable summary that
// links to the account detail page — no inline activity dropdown.
// ─────────────────────────────────────────────────────────────
function ScreenAccounts({ th }) {
  const total = MOCK.accounts.reduce((s, a) => s + a.balance, 0);
  const [openGroups, setOpenGroups] = React.useState({ cash: true, credit: true, invest: true, loan: false });
  const toggleGroup = (id) => setOpenGroups((o) => ({ ...o, [id]: !o[id] }));

  // Group accounts by group id (keep group order from MOCK.accountGroups)
  const groupedAccounts = MOCK.accountGroups
    .map((g) => ({ ...g, accounts: MOCK.accounts.filter((a) => a.group === g.id) }))
    .filter((g) => g.accounts.length > 0 || g.id === 'loan'); // show empty Loan group as add-prompt

  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <div style={{ paddingTop: STATUS_PAD + 8 }}>
          <ScreenHeader th={th} title="Accounts" trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="plus" size={16}/></div>}/>
        </div>

        {/* Hero — net worth */}
        <div style={{ padding: '0 24px 22px' }}>
          <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1.2, textTransform: 'uppercase' }}>Net worth · all accounts</div>
          <div style={{ fontFamily: th.display, fontSize: 52, letterSpacing: -2, lineHeight: 1, marginTop: 6, fontWeight: 400 }}>
            <Money value={total} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
          </div>
          <div style={{ fontSize: 12, color: th.pos, marginTop: 6 }}>+ <Money value={812} currency={th.currency}/> this month</div>
        </div>

        {/* Grouped accounts */}
        <div style={{ padding: '0 20px', display: 'flex', flexDirection: 'column', gap: 14 }}>
          {groupedAccounts.map((g) => {
            const groupTotal = g.accounts.reduce((s, a) => s + a.balance, 0);
            const isOpen = !!openGroups[g.id];
            const empty = g.accounts.length === 0;
            return (
              <div key={g.id}>
                {/* Group header */}
                <div onClick={() => toggleGroup(g.id)} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '0 4px 8px', cursor: 'pointer' }}>
                  <Icon name={isOpen ? 'chev-d' : 'chev'} size={12} style={{ color: th.muted }}/>
                  <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic', letterSpacing: -0.2, flex: 1 }}>{g.name}</div>
                  <span style={{ fontFamily: th.mono, fontSize: 11, color: empty ? th.muted : th.ink2, letterSpacing: 0.3 }}>
                    {empty ? '—' : (
                      <>
                        {g.accounts.length} <span style={{ color: th.muted }}>· </span>
                        <span style={{ fontWeight: 500, color: groupTotal < 0 ? th.neg : th.ink }}>
                          {groupTotal < 0 ? '−' : ''}{fmtMoneyShort(groupTotal, th.currency)}
                        </span>
                      </>
                    )}
                  </span>
                </div>
                {/* Group body */}
                {isOpen && (
                  empty ? (
                    <div style={{ height: 52, borderRadius: 12, border: `1px dashed ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, color: th.muted, fontSize: 12 }}>
                      <Icon name="plus" size={14}/>Add a {g.name.toLowerCase()} account
                    </div>
                  ) : (
                    <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden' }}>
                      {g.accounts.map((a, i) => (
                        <div key={a.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '14px 14px', borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
                          <div style={{ width: 38, height: 38, borderRadius: 8, background: a.color, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: th.mono, fontSize: 10, fontWeight: 600, letterSpacing: 0.5, flexShrink: 0 }}>{a.last4.slice(-2)}</div>
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <div style={{ fontSize: 14, fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{a.name}</div>
                            <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.5, marginTop: 2 }}>•••• {a.last4}</div>
                          </div>
                          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                            <Sparkline values={[20,30,18,42,52,38,45,60,48,55,72,68,75]} width={56} height={20} color={a.balance < 0 ? th.neg : th.accent} stroke={1.2} fillOpacity={0.08}/>
                            <div style={{ textAlign: 'right', minWidth: 78 }}>
                              <div style={{ fontFamily: th.body, fontSize: 16, fontWeight: 500, lineHeight: 1, color: a.balance < 0 ? th.neg : th.ink, fontVariantNumeric: 'tabular-nums' }}>
                                {a.balance < 0 ? '−' : ''}<Money value={Math.abs(a.balance)} currency={th.currency}/>
                              </div>
                            </div>
                            <Icon name="chev" size={12} style={{ color: th.muted, flexShrink: 0 }}/>
                          </div>
                        </div>
                      ))}
                    </div>
                  )
                )}
              </div>
            );
          })}
          {/* Add account */}
          <div style={{ marginTop: 4, height: 52, borderRadius: 12, border: `1px dashed ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, color: th.muted, fontSize: 13 }}>
            <Icon name="plus" size={16}/>Link a new account
          </div>
        </div>
      </div>
      <MobileTabBar th={th} active="accounts"/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Screen · Budgets
// ─────────────────────────────────────────────────────────────
function ScreenBudgets({ th }) {
  const totalSpent = MOCK.categories.reduce((s, c) => s + c.spent, 0);
  const totalBudget = MOCK.categories.reduce((s, c) => s + c.budget, 0);
  const pct = (totalSpent / totalBudget) * 100;
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <div style={{ paddingTop: STATUS_PAD + 8 }}>
          <ScreenHeader th={th} title="Budgets" back={false} trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="edit" size={14}/></div>}/>
        </div>

        <div style={{ padding: '0 24px 22px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 22 }}>
            <Ring value={totalSpent} max={totalBudget} size={120} stroke={10} color={th.accent} track={th.paperAlt}>
              <div style={{ textAlign: 'center' }}>
                <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.6, lineHeight: 1 }}>{Math.round(pct)}%</div>
                <div style={{ fontSize: 9, color: th.muted, letterSpacing: 1, marginTop: 2 }}>USED</div>
              </div>
            </Ring>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1, textTransform: 'uppercase' }}>Spent of budget</div>
              <div style={{ fontFamily: th.display, fontSize: 30, letterSpacing: -0.6, marginTop: 2 }}><Money value={totalSpent} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/></div>
              <div style={{ fontSize: 12, color: th.muted, marginTop: 2 }}>of <Money value={totalBudget} currency={th.currency}/></div>
              <div style={{ marginTop: 8, padding: '4px 10px', display: 'inline-flex', alignItems: 'center', gap: 6, background: `${th.pos}1a`, color: th.pos, borderRadius: 10, fontSize: 11, fontWeight: 500 }}>
                <Icon name="check" size={12}/>On track for May
              </div>
            </div>
          </div>
        </div>

        {/* Per-category budgets */}
        <div style={{ padding: '0 20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8, padding: '0 4px' }}>
            <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic' }}>Categories</div>
            <span style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.8 }}>SPENT / BUDGET</span>
          </div>
          {MOCK.categories.map((c) => {
            const cpct = (c.spent / c.budget) * 100;
            const over = cpct > 100;
            const remaining = c.budget - c.spent;
            return (
              <div key={c.id} style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 14, marginBottom: 8, display: 'flex', alignItems: 'center', gap: 14 }}>
                <div style={{ width: 38, height: 38, borderRadius: 19, background: `oklch(0.92 0.04 ${c.hue})`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, flexShrink: 0 }}>
                  <Icon name={c.icon} size={18}/>
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                    <div style={{ fontSize: 14, fontWeight: 500 }}>{c.name}</div>
                    <div style={{ fontFamily: th.mono, fontSize: 11, color: over ? th.neg : th.ink }}>
                      {fmtMoneyShort(c.spent, th.currency)} / {fmtMoneyShort(c.budget, th.currency)}
                    </div>
                  </div>
                  <div style={{ height: 3, background: th.paperAlt, borderRadius: 2, overflow: 'hidden', marginTop: 6, position: 'relative' }}>
                    <div style={{ width: `${Math.min(cpct, 100)}%`, height: '100%', background: over ? th.neg : th.accent }}/>
                  </div>
                  <div style={{ fontSize: 11, color: over ? th.neg : th.muted, marginTop: 4 }}>
                    {over ? `${fmtMoneyShort(-remaining, th.currency)} over` : `${fmtMoneyShort(remaining, th.currency)} left`}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>
      <MobileTabBar th={th} active="budgets"/>
    </div>
  );
}
function ScreenSettings({ th }) {
  const Section = ({ title, items }) => (
    <div style={{ marginBottom: 22 }}>
      <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.2, color: th.muted, textTransform: 'uppercase', padding: '0 4px 8px' }}>{title}</div>
      <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden' }}>
        {items.map((it, i) => (
          <div key={it.l} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 16px', borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
            <div style={{ width: 30, height: 30, borderRadius: 15, background: th.paperAlt, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink2 }}><Icon name={it.i} size={14}/></div>
            <div style={{ flex: 1, fontSize: 14 }}>{it.l}</div>
            {it.toggle != null ? (
              <div style={{ width: 38, height: 22, borderRadius: 11, background: it.toggle ? th.accent : th.paperAlt, position: 'relative', flexShrink: 0 }}>
                <div style={{ position: 'absolute', top: 2, [it.toggle ? 'right' : 'left']: 2, width: 18, height: 18, borderRadius: 9, background: '#fff', boxShadow: '0 1px 2px rgba(0,0,0,0.15)' }}/>
              </div>
            ) : (
              <span style={{ fontSize: 13, color: th.muted, display: 'flex', alignItems: 'center', gap: 4 }}>
                {it.v}<Icon name="chev" size={12}/>
              </span>
            )}
          </div>
        ))}
      </div>
    </div>
  );
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 30 }}>
        <div style={{ paddingTop: STATUS_PAD + 8 }}>
          <ScreenHeader th={th} title="Settings" back={true} trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="search" size={16}/></div>}/>
        </div>

        {/* Profile */}
        <div style={{ padding: '0 20px 22px', display: 'flex', alignItems: 'center', gap: 14 }}>
          <MerchantGlyph name="Alex Morgan" size={64} bg={th.accent} fg="#fff"/>
          <div style={{ flex: 1 }}>
            <div style={{ fontFamily: th.display, fontSize: 22, letterSpacing: -0.3 }}>Alex Morgan</div>
            <div style={{ fontSize: 12, color: th.muted }}>alex@morgan.co · Personal plan</div>
            <div style={{ marginTop: 8, padding: '4px 10px', display: 'inline-flex', background: th.paperAlt, borderRadius: 10, fontSize: 11, color: th.ink2, fontWeight: 500 }}>Edit profile →</div>
          </div>
        </div>

        <div style={{ padding: '0 20px' }}>
          <Section title="Preferences" items={[
            { i: 'wallet',   l: 'Default currency', v: 'USD' },
            { i: 'tag',      l: 'Categories',       v: '8 active' },
            { i: 'menu',     l: 'Tab layout',       v: '5 tabs' },
            { i: 'bell',     l: 'Notifications',    toggle: true },
            { i: 'target',   l: 'Budget alerts',    toggle: true },
          ]}/>
          <Section title="Data" items={[
            { i: 'wallet',   l: 'Linked accounts',  v: '4' },
            { i: 'sync',     l: 'Auto-categorize',  toggle: true },
            { i: 'doc',      l: 'Export CSV',       v: '' },
            { i: 'cog',      l: 'Backup & sync',    v: 'iCloud' },
          ]}/>
          <Section title="Security" items={[
            { i: 'check',    l: 'Face ID',          toggle: true },
            { i: 'cog',      l: 'Change passcode',  v: '' },
            { i: 'doc',      l: 'Privacy policy',   v: '' },
          ]}/>

          <div style={{ textAlign: 'center', padding: '6px 0 20px', fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.8 }}>
            FINCH · v2.6.0 (build 421)
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Screen · Scheduled (calendar embed + upcoming list)
// ─────────────────────────────────────────────────────────────
function ScreenScheduled({ th }) {
  // Build a 6×7 calendar grid for May 2026 (May 1 = Friday).
  // Schedule overlay: bills + subscriptions on their due dates.
  const events = [
    { day: 30, label: 'ConEd',        amount:   84, kind: 'bill' },
    { day: 22, label: 'Spotify',      amount:  -11.99, kind: 'sub' },
    { day: 19, label: 'Netflix',      amount:  -22.99, kind: 'sub' },
    { day: 15, label: 'Rent',         amount: 1850, kind: 'bill' },
    { day: 14, label: 'NYT',          amount:   -4, kind: 'sub' },
    { day: 22, label: 'Payday',       amount: 2900, kind: 'income' },
  ];
  const eventsByDay = {};
  events.forEach((e) => { (eventsByDay[e.day] = eventsByDay[e.day] || []).push(e); });

  const days = [];
  for (let i = 0; i < 4; i++) days.push(null); // pad to Friday (May 1)
  for (let i = 1; i <= 31; i++) days.push(i);
  while (days.length % 7) days.push(null);

  // Upcoming combined list (next 30 days, sorted)
  const upcoming = [
    { id: 'u1', day: 30, month: 'May', label: 'ConEd Electric',    amount: -84,    type: 'Bill',     freq: 'monthly' },
    { id: 'u2', day:  4, month: 'Jun', label: 'Verizon Fios',      amount: -69,    type: 'Bill',     freq: 'monthly' },
    { id: 'u3', day:  5, month: 'Jun', label: 'Payday · Acme',     amount: 2900,   type: 'Income',   freq: 'biweekly' },
    { id: 'u4', day:  7, month: 'Jun', label: 'Amex Gold',         amount: -842,   type: 'Bill',     freq: 'monthly' },
    { id: 'u5', day:  8, month: 'Jun', label: 'iCloud+',           amount: -9.99,  type: 'Sub',      freq: 'monthly' },
    { id: 'u6', day: 14, month: 'Jun', label: 'NYT',               amount: -4,     type: 'Sub',      freq: 'monthly' },
    { id: 'u7', day: 15, month: 'Jun', label: 'Rent · Greene St.', amount: -1850,  type: 'Bill',     freq: 'monthly' },
  ];
  const totalOut = upcoming.filter(u => u.amount < 0).reduce((s, u) => s + u.amount, 0);
  const totalIn  = upcoming.filter(u => u.amount > 0).reduce((s, u) => s + u.amount, 0);

  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <div style={{ paddingTop: STATUS_PAD + 8 }}>
          <ScreenHeader th={th} title="Scheduled" back={false} trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="plus" size={16}/></div>}/>
        </div>

        {/* Stat strip */}
        <div style={{ padding: '0 24px 18px' }}>
          <div style={{ fontSize: 10, color: th.muted, letterSpacing: 1.2, textTransform: 'uppercase' }}>Next 30 days</div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 14, marginTop: 6 }}>
            <div style={{ fontFamily: th.display, fontSize: 44, letterSpacing: -1.6, lineHeight: 1, color: th.ink }}>
              <Money value={Math.abs(totalOut)} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
            </div>
            <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 16, color: th.muted }}>going out</div>
          </div>
          <div style={{ fontSize: 12, color: th.muted, marginTop: 4 }}>
            <span style={{ color: th.pos, fontWeight: 500 }}>+<Money value={totalIn} currency={th.currency}/></span> incoming · net <Money value={totalIn + totalOut} currency={th.currency}/>
          </div>
        </div>

        {/* Calendar */}
        <div style={{ margin: '0 20px 20px', background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 14 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={{ fontFamily: th.display, fontSize: 20, letterSpacing: -0.3 }}>May 2026</div>
              <span style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1 }}>WEEK 21</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
              <div style={{ width: 28, height: 28, borderRadius: 14, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.muted }}><Icon name="chev-l" size={14}/></div>
              <div style={{ width: 28, height: 28, borderRadius: 14, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="chev" size={14}/></div>
            </div>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7,1fr)', gap: 4, marginBottom: 6 }}>
            {['M','T','W','T','F','S','S'].map((d, i) => (
              <div key={i} style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, textAlign: 'center', letterSpacing: 1 }}>{d}</div>
            ))}
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7,1fr)', gap: 4 }}>
            {days.map((d, i) => {
              if (!d) return <div key={i} style={{ aspectRatio: '1' }}/>;
              const evs = eventsByDay[d] || [];
              const isToday = d === 24;
              const isPast = d < 24;
              return (
                <div key={i} style={{
                  aspectRatio: '1', position: 'relative', padding: 4,
                  background: isToday ? th.ink : 'transparent',
                  color: isToday ? th.paper : (isPast ? th.muted : th.ink),
                  borderRadius: 6,
                  border: !isToday ? `0.5px solid ${th.line}` : 'none',
                }}>
                  <div style={{ fontSize: 11, fontWeight: 500, lineHeight: 1 }}>{d}</div>
                  {evs.length > 0 && (
                    <div style={{ position: 'absolute', bottom: 4, left: 4, right: 4, display: 'flex', gap: 2, justifyContent: 'center' }}>
                      {evs.slice(0, 3).map((e, j) => (
                        <span key={j} style={{
                          width: 5, height: 5, borderRadius: '50%',
                          background: e.kind === 'income' ? th.pos : e.kind === 'bill' ? th.accent : th.warn,
                        }}/>
                      ))}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
          <div style={{ display: 'flex', gap: 14, marginTop: 12, padding: '10px 4px 0', borderTop: `0.5px solid ${th.line}`, fontSize: 11 }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 5, color: th.ink2 }}><span style={{ width: 7, height: 7, borderRadius: 4, background: th.accent }}/>Bill</span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 5, color: th.ink2 }}><span style={{ width: 7, height: 7, borderRadius: 4, background: th.warn }}/>Subscription</span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 5, color: th.ink2 }}><span style={{ width: 7, height: 7, borderRadius: 4, background: th.pos }}/>Income</span>
          </div>
        </div>

        {/* Upcoming list */}
        <div style={{ padding: '0 24px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 10 }}>
            <div style={{ fontFamily: th.display, fontSize: 20, fontStyle: 'italic' }}>Upcoming</div>
            <span style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.8 }}>{upcoming.length} ITEMS</span>
          </div>
          {upcoming.map((u, i) => {
            const inc = u.amount > 0;
            return (
              <div key={u.id} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '12px 0', borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
                <div style={{ width: 44, textAlign: 'center', flexShrink: 0 }}>
                  <div style={{ fontFamily: th.mono, fontSize: 9, letterSpacing: 1, color: th.muted, textTransform: 'uppercase' }}>{u.month}</div>
                  <div style={{ fontFamily: th.display, fontSize: 22, letterSpacing: -0.4, lineHeight: 1, marginTop: 1 }}>{u.day}</div>
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14, fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{u.label}</div>
                  <div style={{ fontSize: 11, color: th.muted, marginTop: 2, display: 'flex', alignItems: 'center', gap: 6 }}>
                    <span style={{ width: 6, height: 6, borderRadius: 3, background: u.type === 'Income' ? th.pos : u.type === 'Bill' ? th.accent : th.warn }}/>
                    {u.type} · {u.freq}
                  </div>
                </div>
                <Money value={u.amount} currency={th.currency} signed={inc} style={{ fontSize: 14, fontWeight: 500, color: inc ? th.pos : th.ink }}/>
              </div>
            );
          })}
        </div>
      </div>
      <MobileTabBar th={th} active="scheduled"/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Optional tabs — Activity / Goals / Subscriptions / Reports.
// These are NOT shown in the default tab bar; users add them via
// Settings → Tab layout. Each renders with `active="more"` since
// they're not pinned, and the tab bar's "more" hint stays inert.
// ─────────────────────────────────────────────────────────────

// ScreenActivity — cross-account transaction feed (the "Activity" optional
// tab). Renders the same content as ScreenTransactions but with its own
// active state so the tabbar correctly reflects it being a current tab.
function ScreenActivity({ th }) {
  return <ScreenTransactionsImpl th={th} activeTab="activity"/>;
}

// Refactor ScreenTransactions to share its body with ScreenActivity. The
// original ScreenTransactions stays as a drill-in alias (active=insights).
function ScreenTransactionsImpl({ th, activeTab = 'insights' }) {
  const groups = {};
  MOCK.transactions.forEach((tx) => { (groups[tx.date] = groups[tx.date] || []).push(tx); });
  const dates = Object.keys(groups).sort().reverse();
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ paddingTop: STATUS_PAD + 8 }}>
        <ScreenHeader th={th} title="Activity" trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="filter" size={16}/></div>}/>
      </div>

      <div style={{ height: 'calc(100% - 100px)', overflowY: 'auto', paddingBottom: 110 }}>
        {/* Sub-summary */}
        <div style={{ padding: '0 20px 16px', display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
          <div>
            <div style={{ fontFamily: th.display, fontSize: 30, letterSpacing: -0.8, lineHeight: 1 }}>{fmtMoneyShort(MOCK.monthSpent, th.currency)}</div>
            <div style={{ fontSize: 11, color: th.muted, marginTop: 4 }}>May · {MOCK.transactions.length} transactions</div>
          </div>
          <div style={{ display: 'flex', gap: 6 }}>
            {['All','Out','In'].map((t, i) => (
              <div key={t} style={{ padding: '6px 12px', borderRadius: 6, fontSize: 11, fontWeight: 500, background: i === 0 ? th.ink : 'transparent', color: i === 0 ? th.paper : th.muted, border: i === 0 ? 'none' : `1px solid ${th.line}` }}>{t}</div>
            ))}
          </div>
        </div>

        <div style={{ margin: '0 20px 18px', height: 38, borderRadius: 19, background: th.paperAlt, display: 'flex', alignItems: 'center', gap: 10, padding: '0 14px', color: th.muted, fontSize: 13 }}>
          <Icon name="search" size={14}/>Search merchants, categories…
          <Icon name="mic" size={14} style={{ marginLeft: 'auto' }}/>
        </div>

        {dates.slice(0, 5).map((d) => {
          const dayTotal = groups[d].reduce((s, t) => s + t.amount, 0);
          const dayLabel = d === '2026-05-24' ? 'Today' : d === '2026-05-23' ? 'Yesterday' : new Date(d).toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' });
          return (
            <div key={d} style={{ marginBottom: 6 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', padding: '8px 20px', fontFamily: th.mono, fontSize: 10, letterSpacing: 1.2, color: th.muted, textTransform: 'uppercase' }}>
                <span>{dayLabel.toUpperCase()}</span>
                <span>{dayTotal > 0 ? '+' : ''}{fmtMoneyShort(dayTotal, th.currency)}</span>
              </div>
              <div style={{ background: th.card }}>
                {groups[d].map((tx, i) => {
                  const cat = catById(tx.category);
                  const inc = tx.amount > 0;
                  return (
                    <div key={tx.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 20px', borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
                      <MerchantGlyph name={tx.merchant} size={36} hue={cat.hue}/>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontSize: 14, fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{tx.merchant}</div>
                        <div style={{ fontSize: 11, color: th.muted, marginTop: 2, display: 'flex', alignItems: 'center', gap: 6 }}>
                          <CatDot hue={cat.hue}/>{cat.name || 'Income'}
                          {tx.pending && <span style={{ color: th.warn }}>· pending</span>}
                        </div>
                      </div>
                      <Money value={tx.amount} currency={th.currency} signed={inc} style={{ fontSize: 14, fontWeight: 500, color: inc ? th.pos : th.ink, fontVariantNumeric: 'tabular-nums' }}/>
                    </div>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>
      <MobileTabBar th={th} active={activeTab} extraTabs={activeTab === 'activity' ? [{ id: 'activity', icon: 'doc', label: 'Activity' }] : null}/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Screen · Goals (optional tab)
// ─────────────────────────────────────────────────────────────
function ScreenGoals({ th }) {
  const totalSaved = MOCK.goals.reduce((s, g) => s + g.saved, 0);
  const totalTarget = MOCK.goals.reduce((s, g) => s + g.target, 0);
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <div style={{ paddingTop: STATUS_PAD + 8 }}>
          <ScreenHeader th={th} title="Goals" trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="plus" size={16}/></div>}/>
        </div>

        {/* Aggregate */}
        <div style={{ padding: '0 24px 22px' }}>
          <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1.2, textTransform: 'uppercase' }}>Saved · {MOCK.goals.length} goals</div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginTop: 6 }}>
            <div style={{ fontFamily: th.display, fontSize: 48, letterSpacing: -1.8, lineHeight: 1 }}>
              <Money value={totalSaved} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
            </div>
            <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 16, color: th.muted }}>of {fmtMoneyShort(totalTarget, th.currency)}</div>
          </div>
          <div style={{ marginTop: 10, height: 4, background: th.paperAlt, borderRadius: 2, overflow: 'hidden' }}>
            <div style={{ width: `${(totalSaved / totalTarget) * 100}%`, height: '100%', background: th.accent }}/>
          </div>
        </div>

        {/* Goals */}
        <div style={{ padding: '0 20px', display: 'flex', flexDirection: 'column', gap: 12 }}>
          {MOCK.goals.map((g) => {
            const pct = (g.saved / g.target) * 100;
            return (
              <div key={g.id} style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 18, display: 'flex', gap: 16, alignItems: 'center' }}>
                <Ring value={g.saved} max={g.target} size={66} stroke={6} color={`oklch(0.65 0.14 ${g.hue})`} track={th.paperAlt}>
                  <span style={{ fontFamily: th.mono, fontSize: 12, fontWeight: 600 }}>{Math.round(pct)}%</span>
                </Ring>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontFamily: th.display, fontSize: 20, letterSpacing: -0.3, lineHeight: 1.1 }}>{g.name}</div>
                  <div style={{ fontSize: 12, color: th.muted, marginTop: 4 }}>ETA {g.eta}</div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginTop: 8 }}>
                    <span style={{ fontFamily: th.mono, fontSize: 12 }}>
                      <Money value={g.saved} currency={th.currency} style={{ fontWeight: 600 }}/>
                      <span style={{ color: th.muted }}> / {fmtMoneyShort(g.target, th.currency)}</span>
                    </span>
                    <span style={{ fontSize: 11, color: th.pos, fontWeight: 500 }}>+ {fmtMoneyShort(g.target / 12, th.currency)} / mo</span>
                  </div>
                </div>
              </div>
            );
          })}
          <div style={{ height: 52, borderRadius: 12, border: `1px dashed ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, color: th.muted, fontSize: 13 }}>
            <Icon name="plus" size={16}/>New savings goal
          </div>
        </div>
      </div>
      <MobileTabBar th={th} active="goals" extraTabs={[{ id: 'goals', icon: 'sparkle', label: 'Goals' }]}/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Screen · Subscriptions (optional tab)
// ─────────────────────────────────────────────────────────────
function ScreenSubscriptions({ th }) {
  const monthlyTotal = MOCK.subscriptions.reduce((s, x) => s + x.amount, 0);
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <div style={{ paddingTop: STATUS_PAD + 8 }}>
          <ScreenHeader th={th} title="Subscriptions" trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="plus" size={16}/></div>}/>
        </div>

        <div style={{ padding: '0 24px 18px' }}>
          <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1.2, textTransform: 'uppercase' }}>{MOCK.subscriptions.length} active · monthly</div>
          <div style={{ fontFamily: th.display, fontSize: 50, letterSpacing: -1.8, lineHeight: 1, marginTop: 4 }}>
            <Money value={monthlyTotal} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
          </div>
          <div style={{ fontSize: 12, color: th.muted, marginTop: 4 }}>
            <Money value={monthlyTotal * 12} currency={th.currency}/> / year · <span style={{ color: th.accent }}>review →</span>
          </div>
        </div>

        {/* Spend over month strip */}
        <div style={{ margin: '0 20px 18px', padding: 16, background: th.card, border: `1px solid ${th.line}`, borderRadius: 14 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8 }}>
            <div style={{ fontSize: 12, fontWeight: 600 }}>Annual cost · 12 months</div>
            <span style={{ fontFamily: th.mono, fontSize: 10, color: th.muted }}>{fmtMoneyShort(monthlyTotal * 12, th.currency)}</span>
          </div>
          <BarChart values={[59,68,68,72,68,68,72,68,68,79,79,79]} labels={['J','F','M','A','M','J','J','A','S','O','N','D']} width={310} height={60} color={th.muted} highlight={th.accent} muted={th.paperAlt}/>
        </div>

        {/* List */}
        <div style={{ padding: '0 20px' }}>
          <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1.2, textTransform: 'uppercase', marginBottom: 8 }}>Active subscriptions</div>
          {MOCK.subscriptions.map((s, i) => (
            <div key={s.id} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '12px 0', borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
              <div style={{ width: 40, height: 40, borderRadius: 10, background: `oklch(0.82 0.10 ${s.logoHue})`, color: th.ink, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: th.display, fontWeight: 500, fontSize: 18, flexShrink: 0 }}>{s.name.charAt(0)}</div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 14, fontWeight: 500 }}>{s.name}</div>
                <div style={{ fontSize: 11, color: th.muted, marginTop: 2 }}>{s.cadence} · next {s.next}</div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontFamily: th.mono, fontSize: 13, fontWeight: 600 }}><Money value={s.amount} currency={th.currency}/></div>
                <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, marginTop: 2 }}>{fmtMoneyShort(s.amount * 12, th.currency)}/yr</div>
              </div>
            </div>
          ))}
        </div>
      </div>
      <MobileTabBar th={th} active="subs" extraTabs={[{ id: 'subs', icon: 'sync', label: 'Subs' }]}/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Screen · Tab Layout (settings sub-screen)
// Shows the active tabs + available extras the user can add.
// ─────────────────────────────────────────────────────────────
const ALL_TABS = [
  { id: 'accounts',  icon: 'wallet',   label: 'Accounts',      desc: 'Balances + activity per account' },
  { id: 'budgets',   icon: 'target',   label: 'Budgets',       desc: 'Spending by category vs plan' },
  { id: 'add',       icon: 'plus',     label: 'Add',           desc: 'Center button · always pinned', pinned: true },
  { id: 'scheduled', icon: 'calendar', label: 'Scheduled',     desc: 'Calendar of bills, subs, income' },
  { id: 'insights',  icon: 'chart',    label: 'Insights',      desc: 'Analytics and patterns' },
  { id: 'activity',  icon: 'doc',      label: 'Activity',      desc: 'Cross-account transaction feed' },
  { id: 'goals',     icon: 'sparkle',  label: 'Goals',         desc: 'Savings goals progress' },
  { id: 'subs',      icon: 'sync',     label: 'Subscriptions', desc: 'Recurring spend manager' },
  { id: 'reports',   icon: 'doc',      label: 'Reports',       desc: 'Exportable monthly statements' },
];

function ScreenTabLayout({ th }) {
  // Default active set
  const active = ['accounts','budgets','add','scheduled','insights'];
  const available = ALL_TABS.filter((t) => !active.includes(t.id));

  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 20 }}>
        <div style={{ paddingTop: STATUS_PAD + 8 }}>
          <ScreenHeader th={th} title="Tab layout" back={true} trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.accent, fontSize: 13, fontWeight: 500, padding: '0 14px', width: 'auto' }}>Done</div>}/>
        </div>

        <div style={{ padding: '0 24px 18px' }}>
          <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 18, lineHeight: 1.35, color: th.ink2 }}>
            Five tabs always show in the bar at the bottom. Drag to reorder, swap any of them with one from <b>Available</b> below.
          </div>
        </div>

        {/* Current preview */}
        <div style={{ margin: '0 20px 18px', background: th.card, border: `1px solid ${th.line}`, borderRadius: 16, padding: 16 }}>
          <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1.2, marginBottom: 14 }}>PREVIEW</div>
          <div style={{ height: 56, borderRadius: 28, background: th.paperAlt, display: 'flex', alignItems: 'center', justifyContent: 'space-around' }}>
            {active.map((id) => {
              const tab = ALL_TABS.find(t => t.id === id);
              if (tab.id === 'add') return (
                <div key="add" style={{ width: 40, height: 40, borderRadius: 20, background: th.accent, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  <Icon name="plus" size={20} stroke={2}/>
                </div>
              );
              return (
                <div key={tab.id} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2, color: th.ink }}>
                  <Icon name={tab.icon} size={18}/>
                  <span style={{ fontSize: 9, fontWeight: 500 }}>{tab.label}</span>
                </div>
              );
            })}
          </div>
        </div>

        {/* Active tabs list */}
        <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1.2, padding: '8px 24px' }}>IN YOUR TAB BAR · 5</div>
        <div style={{ margin: '0 20px 18px', background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden' }}>
          {active.map((id, i) => {
            const tab = ALL_TABS.find(t => t.id === id);
            return (
              <div key={tab.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', borderTop: i ? `0.5px solid ${th.line}` : 'none', background: tab.pinned ? th.paperAlt : 'transparent' }}>
                <div style={{ color: th.muted, cursor: 'grab' }}>
                  <svg width="10" height="14" viewBox="0 0 10 14" fill="currentColor"><circle cx="2" cy="2.5" r="1"/><circle cx="8" cy="2.5" r="1"/><circle cx="2" cy="7" r="1"/><circle cx="8" cy="7" r="1"/><circle cx="2" cy="11.5" r="1"/><circle cx="8" cy="11.5" r="1"/></svg>
                </div>
                <div style={{ width: 32, height: 32, borderRadius: 16, background: th.paperAlt, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, flexShrink: 0 }}>
                  <Icon name={tab.icon} size={15}/>
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14, fontWeight: 500, display: 'flex', alignItems: 'center', gap: 6 }}>
                    {tab.label}
                    {tab.pinned && <span style={{ fontFamily: th.mono, fontSize: 9, letterSpacing: 0.6, color: th.muted, background: th.card, padding: '1px 6px', borderRadius: 4, border: `0.5px solid ${th.line}` }}>PINNED</span>}
                  </div>
                  <div style={{ fontSize: 11, color: th.muted, marginTop: 1 }}>{tab.desc}</div>
                </div>
                {!tab.pinned && (
                  <div style={{ width: 28, height: 28, borderRadius: 14, background: `${th.neg}1a`, color: th.neg, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <Icon name="x" size={13}/>
                  </div>
                )}
              </div>
            );
          })}
        </div>

        {/* Available tabs */}
        <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1.2, padding: '8px 24px' }}>AVAILABLE · TAP TO ADD</div>
        <div style={{ margin: '0 20px', background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden' }}>
          {available.map((tab, i) => (
            <div key={tab.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
              <div style={{ width: 32, height: 32, borderRadius: 16, background: th.paperAlt, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, flexShrink: 0 }}>
                <Icon name={tab.icon} size={15}/>
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 14, fontWeight: 500 }}>{tab.label}</div>
                <div style={{ fontSize: 11, color: th.muted, marginTop: 1 }}>{tab.desc}</div>
              </div>
              <div style={{ width: 28, height: 28, borderRadius: 14, background: `${th.pos}1a`, color: th.pos, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Icon name="plus" size={14} stroke={2}/>
              </div>
            </div>
          ))}
        </div>

        <div style={{ textAlign: 'center', padding: '20px 24px', fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.8 }}>
          The bottom bar always shows exactly 5 tabs · Add sits in the middle
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenAddExpense, ScreenTransactions, ScreenTxDetail, ScreenInsights, ScreenAccounts, ScreenBudgets, ScreenSettings, ScreenScheduled, ScreenActivity, ScreenGoals, ScreenSubscriptions, ScreenTabLayout, ScreenHeader });
