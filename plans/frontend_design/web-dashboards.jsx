// Six web dashboard variations.
// Each is 1280×800, rendered as content inside ChromeWindow.

const WEB_W = 1280;
const WEB_H = 800;

// Shared sidebar component (used by several variations)
function WebSidebar({ th, active = 'accts', collapsed = false }) {
  const items = [
    { id: 'accts',   icon: 'wallet',   label: 'Accounts' },
    { id: 'budget',  icon: 'target',   label: 'Budgets' },
    { id: 'bills',   icon: 'calendar', label: 'Scheduled' },
    { id: 'insights',icon: 'chart',    label: 'Insights' },
  ];
  const more = [
    { id: 'activity',icon: 'doc',      label: 'Activity' },
    { id: 'goals',   icon: 'sparkle',  label: 'Goals' },
    { id: 'subs',    icon: 'sync',     label: 'Subscriptions' },
    { id: 'reports', icon: 'doc',      label: 'Reports' },
  ];
  const Row = ({ it }) => (
    <div key={it.id} style={{
      display: 'flex', alignItems: 'center', gap: 12, padding: '9px 10px', borderRadius: 8,
      background: it.id === active ? th.ink : 'transparent',
      color: it.id === active ? th.paper : th.ink2,
      fontSize: 13, fontWeight: it.id === active ? 500 : 400,
    }}>
      <Icon name={it.icon} size={16} stroke={1.5}/>
      {!collapsed && <span>{it.label}</span>}
    </div>
  );
  return (
    <div style={{
      width: collapsed ? 60 : 220, background: th.paperAlt, color: th.ink,
      padding: '20px 12px', display: 'flex', flexDirection: 'column', gap: 4,
      borderRight: `1px solid ${th.line}`, flexShrink: 0,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '0 8px 18px', borderBottom: `1px solid ${th.line}`, marginBottom: 12 }}>
        <div style={{ width: 28, height: 28, borderRadius: 14, background: th.ink, color: th.paper, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: th.display, fontStyle: 'italic', fontWeight: 500 }}>F</div>
        {!collapsed && <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic', letterSpacing: -0.3 }}>Finch</div>}
      </div>
      {items.map((it) => <Row key={it.id} it={it}/>)}

      {!collapsed && (
        <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1.5, padding: '14px 10px 6px' }}>MORE</div>
      )}
      {more.map((it) => <Row key={it.id} it={it}/>)}

      <div style={{ flex: 1 }}/>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '8px 10px', borderRadius: 8, color: th.muted, fontSize: 13 }}>
        <Icon name="cog" size={16} stroke={1.5}/>{!collapsed && <span>Settings</span>}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 10px', borderRadius: 8, borderTop: `0.5px solid ${th.line}`, marginTop: 4 }}>
        <MerchantGlyph name="Alex Morgan" size={28} bg={th.accent} fg="#fff"/>
        {!collapsed && <div style={{ fontSize: 12, lineHeight: 1.3 }}>
          <div style={{ fontWeight: 500 }}>Alex Morgan</div>
          <div style={{ color: th.muted, fontSize: 11 }}>Personal</div>
        </div>}
      </div>
    </div>
  );
}

// Shared top bar
function WebTopBar({ th, title, sub }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '24px 32px', borderBottom: `1px solid ${th.line}` }}>
      <div>
        <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.6, lineHeight: 1 }}>{title}</div>
        {sub && <div style={{ fontSize: 13, color: th.muted, marginTop: 4 }}>{sub}</div>}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, height: 36, padding: '0 14px', background: th.paperAlt, borderRadius: 18, color: th.muted, fontSize: 13, width: 280 }}>
          <Icon name="search" size={14}/>Search transactions, merchants…
        </div>
        <div style={{ width: 36, height: 36, borderRadius: 18, background: th.paperAlt, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="bell" size={16}/></div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, height: 36, padding: '0 16px', background: th.ink, color: th.paper, borderRadius: 18, fontSize: 13, fontWeight: 500 }}>
          <Icon name="plus" size={14} stroke={2}/>Add expense
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 01 · Editorial — newspaper grid, big serif, hairline rules
// ─────────────────────────────────────────────────────────────
function WebEditorial({ th }) {
  const cats = MOCK.categories.slice(0, 6);
  return (
    <div style={{ height: WEB_H, background: th.paper, color: th.ink, fontFamily: th.body, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
      {/* Masthead */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '18px 40px', borderBottom: `2px solid ${th.ink}` }}>
        <div style={{ fontFamily: th.display, fontSize: 28, fontStyle: 'italic', letterSpacing: -0.5 }}>The Finch</div>
        <div style={{ display: 'flex', gap: 28, fontFamily: th.mono, fontSize: 11, letterSpacing: 1.5, textTransform: 'uppercase', color: th.ink2 }}>
          <span>Dashboard</span><span>Transactions</span><span>Budgets</span><span>Insights</span><span>Settings</span>
        </div>
        <div style={{ fontFamily: th.mono, fontSize: 11, letterSpacing: 1, color: th.muted }}>SAT · 24 MAY 2026</div>
      </div>
      {/* Section head */}
      <div style={{ padding: '10px 40px', borderBottom: `0.5px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontFamily: th.mono, fontSize: 11, letterSpacing: 1.5, textTransform: 'uppercase', color: th.muted }}>
        <span>Vol. III · No. 124 — Personal Finance Edition</span>
        <span>{MOCK.accounts.length} accounts synced · Last 9:41 AM</span>
      </div>

      <div style={{ flex: 1, display: 'grid', gridTemplateColumns: '1.5fr 1fr 1fr', overflow: 'hidden' }}>
        {/* Lead column */}
        <div style={{ padding: '28px 36px', borderRight: `0.5px solid ${th.line}`, overflowY: 'auto' }}>
          <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 2, textTransform: 'uppercase', color: th.muted, marginBottom: 12 }}>The Big Number</div>
          <div style={{ fontFamily: th.display, fontSize: 96, lineHeight: 0.95, letterSpacing: -4, fontWeight: 400 }}>
            <Money value={MOCK.balance} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
          </div>
          <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 18, color: th.ink2, marginTop: 10, marginBottom: 22 }}>
            net balance, May twenty-fourth
          </div>
          <div style={{ display: 'flex', gap: 32, paddingTop: 18, borderTop: `0.5px solid ${th.line}` }}>
            <div>
              <div style={{ fontSize: 10, color: th.muted, letterSpacing: 1.2, textTransform: 'uppercase' }}>Income MTD</div>
              <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.5, marginTop: 6 }}><Money value={MOCK.monthIncome} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/></div>
            </div>
            <div>
              <div style={{ fontSize: 10, color: th.muted, letterSpacing: 1.2, textTransform: 'uppercase' }}>Spend MTD</div>
              <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.5, marginTop: 6 }}><Money value={MOCK.monthSpent} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/></div>
            </div>
            <div>
              <div style={{ fontSize: 10, color: th.muted, letterSpacing: 1.2, textTransform: 'uppercase' }}>Saved</div>
              <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.5, marginTop: 6, color: th.accent }}><Money value={3362} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/></div>
            </div>
          </div>

          <div style={{ marginTop: 32 }}>
            <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 22, marginBottom: 14, letterSpacing: -0.2 }}>This Month, In Pictures</div>
            <BarChart values={MOCK.monthly.map(m => m.v)} labels={MOCK.monthly.map(m => m.m[0])} width={520} height={140} color={th.ink} highlight={th.accent} muted={th.paperAlt}/>
          </div>
        </div>

        {/* Middle — categories */}
        <div style={{ padding: '28px 32px', borderRight: `0.5px solid ${th.line}`, overflowY: 'auto' }}>
          <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 2, textTransform: 'uppercase', color: th.muted, marginBottom: 12, paddingBottom: 8, borderBottom: `0.5px solid ${th.line}` }}>The Categories</div>
          {cats.map((c, i) => {
            const pct = (c.spent / c.budget) * 100;
            const over = pct > 100;
            return (
              <div key={c.id} style={{ padding: '14px 0', borderBottom: i < cats.length - 1 ? `0.5px solid ${th.line}` : 'none' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 6 }}>
                  <div style={{ fontFamily: th.display, fontSize: 18, letterSpacing: -0.2 }}>{c.name}</div>
                  <div style={{ fontFamily: th.mono, fontSize: 12, color: over ? th.neg : th.ink }}>
                    {fmtMoneyShort(c.spent, th.currency)}<span style={{ opacity: 0.4 }}> / {fmtMoneyShort(c.budget, th.currency)}</span>
                  </div>
                </div>
                <div style={{ height: 2, background: th.paperAlt, position: 'relative', overflow: 'hidden' }}>
                  <div style={{ width: `${Math.min(pct, 100)}%`, height: '100%', background: over ? th.neg : th.accent }}/>
                </div>
              </div>
            );
          })}
        </div>

        {/* Right — chronicle */}
        <div style={{ padding: '28px 32px', overflowY: 'auto' }}>
          <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 2, textTransform: 'uppercase', color: th.muted, marginBottom: 12, paddingBottom: 8, borderBottom: `0.5px solid ${th.line}` }}>The Chronicle</div>
          {MOCK.transactions.slice(0, 7).map((tx, i) => {
            const inc = tx.amount > 0;
            return (
              <div key={tx.id} style={{ padding: '10px 0', borderBottom: i < 6 ? `0.5px dotted ${th.line}` : 'none', display: 'flex', alignItems: 'baseline', gap: 12 }}>
                <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.5, width: 38, flexShrink: 0 }}>{tx.date.slice(5).replace('-','/')}</div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 13, fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{tx.merchant}</div>
                  <div style={{ fontSize: 11, color: th.muted, fontStyle: 'italic', fontFamily: th.display }}>{catById(tx.category).name || 'Income'}</div>
                </div>
                <div style={{ fontFamily: th.mono, fontSize: 12, color: inc ? th.pos : th.ink, fontWeight: 500 }}>
                  {inc ? '+' : ''}{fmtMoneyShort(tx.amount, th.currency)}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 02 · Classic Admin — sidebar + grid of cards
// ─────────────────────────────────────────────────────────────
function WebClassic({ th }) {
  return (
    <div style={{ height: WEB_H, background: th.paper, color: th.ink, fontFamily: th.body, display: 'flex', overflow: 'hidden' }}>
      <WebSidebar th={th} active="home"/>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        <WebTopBar th={th} title="Dashboard" sub="Hello Alex, here's where you stand on May 24."/>
        <div style={{ flex: 1, padding: 28, overflowY: 'auto' }}>
          {/* Stat row */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 16, marginBottom: 20 }}>
            {[
              { label: 'Net Balance',  v: MOCK.balance,    color: th.ink,    sub: '+2.1%', sc: th.pos, spark: [4,5,4,6,7,6,8,7,9] },
              { label: 'May Spend',    v: MOCK.monthSpent, color: th.ink,    sub: '−8.4%', sc: th.pos, spark: [9,7,5,6,4,5,3,4,2] },
              { label: 'Income MTD',   v: MOCK.monthIncome,color: th.ink,    sub: 'On track', sc: th.muted, spark: [3,3,3,5,5,5,8,8,8] },
              { label: 'Saved',        v: 3362,            color: th.accent, sub: '+22%',  sc: th.pos, spark: [2,3,3,4,5,6,7,7,8] },
            ].map((s) => (
              <div key={s.label} style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 12, padding: 18 }}>
                <div style={{ fontSize: 11, color: th.muted, letterSpacing: 0.8, textTransform: 'uppercase', marginBottom: 6 }}>{s.label}</div>
                <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
                  <div>
                    <div style={{ fontSize: 24, fontWeight: 600, letterSpacing: -0.5, color: s.color }}><Money value={s.v} currency={th.currency}/></div>
                    <div style={{ fontSize: 11, color: s.sc, marginTop: 4 }}>{s.sub}</div>
                  </div>
                  <Sparkline values={s.spark} width={80} height={32} color={s.color === th.accent ? th.accent : th.muted} stroke={1.5}/>
                </div>
              </div>
            ))}
          </div>

          {/* Main grid */}
          <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: 16 }}>
            {/* Spending overview */}
            <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 12, padding: 22 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 18 }}>
                <div>
                  <div style={{ fontSize: 14, fontWeight: 600 }}>Spending overview</div>
                  <div style={{ fontSize: 12, color: th.muted }}>Last 12 months</div>
                </div>
                <div style={{ display: 'flex', gap: 4, padding: 3, background: th.paperAlt, borderRadius: 8 }}>
                  {['1M','3M','6M','1Y','All'].map((p) => (
                    <div key={p} style={{ padding: '4px 10px', borderRadius: 6, fontSize: 11, fontWeight: 500, background: p === '1Y' ? th.card : 'transparent', color: p === '1Y' ? th.ink : th.muted, boxShadow: p === '1Y' ? '0 1px 2px rgba(0,0,0,0.05)' : 'none' }}>{p}</div>
                  ))}
                </div>
              </div>
              <BarChart values={MOCK.monthly.map(m => m.v)} labels={MOCK.monthly.map(m => m.m)} width={620} height={180} color={th.muted} highlight={th.accent} muted={th.paperAlt}/>
            </div>

            {/* Categories donut */}
            <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 12, padding: 22 }}>
              <div style={{ fontSize: 14, fontWeight: 600, marginBottom: 4 }}>By category</div>
              <div style={{ fontSize: 12, color: th.muted, marginBottom: 12 }}>This month</div>
              <div style={{ display: 'flex', justifyContent: 'center', position: 'relative', marginBottom: 16 }}>
                <Donut slices={MOCK.categories.map(c => ({ value: c.spent, color: `oklch(0.65 0.13 ${c.hue})` }))} size={150} stroke={20} gap={2}/>
                <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
                  <div style={{ fontSize: 11, color: th.muted }}>Total</div>
                  <div style={{ fontSize: 18, fontWeight: 600 }}>{fmtMoneyShort(MOCK.monthSpent, th.currency)}</div>
                </div>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                {MOCK.categories.slice(0, 5).map((c) => (
                  <div key={c.id} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12 }}>
                    <span style={{ width: 8, height: 8, borderRadius: 4, background: `oklch(0.65 0.13 ${c.hue})` }}/>
                    <span style={{ flex: 1, color: th.ink2 }}>{c.name}</span>
                    <span style={{ fontVariantNumeric: 'tabular-nums', fontWeight: 500 }}>{fmtMoneyShort(c.spent, th.currency)}</span>
                  </div>
                ))}
              </div>
            </div>

            {/* Recent transactions */}
            <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 12, padding: 22 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
                <div style={{ fontSize: 14, fontWeight: 600 }}>Recent transactions</div>
                <span style={{ fontSize: 12, color: th.accent, fontWeight: 500 }}>View all →</span>
              </div>
              {MOCK.transactions.slice(0, 5).map((tx, i) => (
                <div key={tx.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 0', borderTop: i ? `1px solid ${th.line}` : 'none' }}>
                  <MerchantGlyph name={tx.merchant} size={32} hue={catById(tx.category).hue}/>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 13, fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{tx.merchant}</div>
                    <div style={{ fontSize: 11, color: th.muted }}>{catById(tx.category).name || 'Income'} · {tx.time}</div>
                  </div>
                  <Money value={tx.amount} currency={th.currency} style={{ fontSize: 13, fontWeight: 500, color: tx.amount > 0 ? th.pos : th.ink }}/>
                </div>
              ))}
            </div>

            {/* Bills */}
            <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 12, padding: 22 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
                <div style={{ fontSize: 14, fontWeight: 600 }}>Upcoming bills</div>
                <span style={{ fontSize: 12, color: th.muted }}>Next 30 days</span>
              </div>
              {MOCK.bills.map((b, i) => (
                <div key={b.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 0', borderTop: i ? `1px solid ${th.line}` : 'none' }}>
                  <div style={{ width: 40, textAlign: 'center', flexShrink: 0 }}>
                    <div style={{ fontSize: 10, color: th.muted, letterSpacing: 0.5, textTransform: 'uppercase' }}>{b.dueDate.split(' ')[0]}</div>
                    <div style={{ fontSize: 16, fontWeight: 600 }}>{b.dueDate.split(' ')[1]}</div>
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 13, fontWeight: 500 }}>{b.name}</div>
                    <div style={{ fontSize: 11, color: th.muted }}>{b.dueIn}</div>
                  </div>
                  <Money value={b.amount} currency={th.currency} style={{ fontSize: 13, fontWeight: 500 }}/>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 03 · Spreadsheet — Bloomberg-esque, dense tabular
// ─────────────────────────────────────────────────────────────
function WebSpreadsheet({ th }) {
  return (
    <div style={{ height: WEB_H, background: th.paper, color: th.ink, fontFamily: th.body, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
      {/* Ticker bar */}
      <div style={{ background: th.ink, color: th.paper, fontFamily: th.mono, fontSize: 11, padding: '8px 16px', display: 'flex', gap: 28, letterSpacing: 0.4 }}>
        <span style={{ opacity: 0.5 }}>FINCH · {MOCK.user.name.toUpperCase()}</span>
        <span><span style={{ opacity: 0.5 }}>NET</span> {fmtMoney(MOCK.balance, th.currency)}</span>
        <span><span style={{ opacity: 0.5 }}>SPEND MTD</span> {fmtMoney(MOCK.monthSpent, th.currency)} <span style={{ color: th.pos }}>−8.4%</span></span>
        <span><span style={{ opacity: 0.5 }}>BUDGET</span> 76% used</span>
        <span><span style={{ opacity: 0.5 }}>SAVINGS RATE</span> 58%</span>
        <span style={{ marginLeft: 'auto', opacity: 0.55 }}>SAT 24 MAY · 09:41 EDT</span>
      </div>

      <div style={{ flex: 1, display: 'grid', gridTemplateColumns: '320px 1fr 320px', overflow: 'hidden', borderTop: `1px solid ${th.line}` }}>
        {/* Left rail — accounts */}
        <div style={{ borderRight: `1px solid ${th.line}`, overflowY: 'auto' }}>
          <div style={{ padding: '10px 16px', fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, background: th.paperAlt, borderBottom: `1px solid ${th.line}` }}>ACCOUNTS · {MOCK.accounts.length}</div>
          {MOCK.accounts.map((a, i) => (
            <div key={a.id} style={{ padding: '14px 16px', borderBottom: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', gap: 12 }}>
              <div style={{ width: 32, height: 32, borderRadius: 6, background: a.color, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, fontWeight: 600, letterSpacing: 0.5, flexShrink: 0 }}>{a.last4.slice(-2)}</div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 12, fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{a.name}</div>
                <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.5 }}>•••• {a.last4} · {a.type.toUpperCase()}</div>
              </div>
              <div style={{ fontFamily: th.mono, fontSize: 12, fontWeight: 500, color: a.balance < 0 ? th.neg : th.ink, textAlign: 'right' }}>
                {a.balance < 0 ? '−' : ''}{fmtMoneyShort(a.balance, th.currency)}
              </div>
            </div>
          ))}
          <div style={{ padding: '10px 16px', fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, background: th.paperAlt, borderBottom: `1px solid ${th.line}`, marginTop: 4 }}>BUDGET STATUS</div>
          {MOCK.categories.slice(0, 6).map((c) => {
            const pct = (c.spent / c.budget) * 100;
            return (
              <div key={c.id} style={{ padding: '10px 16px', borderBottom: `1px solid ${th.line}`, fontFamily: th.mono, fontSize: 11 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
                  <span style={{ color: th.ink2 }}>{c.name}</span>
                  <span style={{ color: pct > 100 ? th.neg : th.ink, fontWeight: 600 }}>{Math.round(pct)}%</span>
                </div>
                <div style={{ height: 3, background: th.paperAlt, position: 'relative' }}>
                  <div style={{ width: `${Math.min(pct, 100)}%`, height: '100%', background: pct > 100 ? th.neg : th.accent }}/>
                </div>
              </div>
            );
          })}
        </div>

        {/* Center — transactions table */}
        <div style={{ overflowY: 'auto', display: 'flex', flexDirection: 'column' }}>
          <div style={{ padding: '10px 20px', background: th.paperAlt, borderBottom: `1px solid ${th.line}`, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted }}>TRANSACTIONS · MAY 2026</span>
            <div style={{ display: 'flex', gap: 6, fontFamily: th.mono, fontSize: 10, color: th.muted }}>
              <span>F · Filter</span><span>S · Sort</span><span>E · Export</span>
            </div>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '70px 1fr 110px 100px 70px 110px', padding: '6px 20px', fontFamily: th.mono, fontSize: 9, letterSpacing: 1.5, color: th.muted, borderBottom: `1px solid ${th.line}`, background: th.paperAlt }}>
            <span>DATE</span><span>MERCHANT</span><span>CATEGORY</span><span>ACCOUNT</span><span>STATUS</span><span style={{ textAlign: 'right' }}>AMOUNT</span>
          </div>
          {MOCK.transactions.map((tx) => {
            const cat = catById(tx.category);
            const acct = acctById(tx.account);
            const inc = tx.amount > 0;
            return (
              <div key={tx.id} style={{ display: 'grid', gridTemplateColumns: '70px 1fr 110px 100px 70px 110px', padding: '9px 20px', fontFamily: th.mono, fontSize: 11, alignItems: 'center', borderBottom: `1px solid ${th.line}` }}>
                <span style={{ color: th.muted }}>{tx.date.slice(5).replace('-','/')}</span>
                <span style={{ fontFamily: th.body, fontSize: 12, fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{tx.merchant}</span>
                <span style={{ color: th.ink2, fontSize: 10, display: 'flex', alignItems: 'center', gap: 5 }}>
                  <CatDot hue={cat.hue}/> {cat.name}
                </span>
                <span style={{ color: th.muted }}>{acct.last4}</span>
                <span style={{ color: tx.pending ? th.warn : th.muted, fontSize: 9 }}>{tx.pending ? 'PENDING' : 'POSTED'}</span>
                <span style={{ textAlign: 'right', fontWeight: 600, color: inc ? th.pos : th.ink }}>
                  {inc ? '+' : ''}{fmtMoney(tx.amount, th.currency)}
                </span>
              </div>
            );
          })}
        </div>

        {/* Right rail — analytics */}
        <div style={{ borderLeft: `1px solid ${th.line}`, overflowY: 'auto' }}>
          <div style={{ padding: '10px 16px', fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, background: th.paperAlt, borderBottom: `1px solid ${th.line}` }}>30-DAY SPEND</div>
          <div style={{ padding: 16, borderBottom: `1px solid ${th.line}` }}>
            <Sparkline values={MOCK.daily} width={280} height={70} color={th.accent} stroke={1.5}/>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: th.mono, fontSize: 9, color: th.muted, marginTop: 4, letterSpacing: 0.5 }}>
              <span>APR 25</span><span>MAY 24</span>
            </div>
          </div>
          <div style={{ padding: '10px 16px', fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, background: th.paperAlt, borderBottom: `1px solid ${th.line}` }}>12-MONTH</div>
          <div style={{ padding: 16, borderBottom: `1px solid ${th.line}` }}>
            <BarChart values={MOCK.monthly.map(m => m.v)} labels={MOCK.monthly.map(m => m.m[0])} width={280} height={90} color={th.muted} highlight={th.accent} muted={th.paperAlt}/>
          </div>
          <div style={{ padding: '10px 16px', fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, background: th.paperAlt, borderBottom: `1px solid ${th.line}` }}>UPCOMING · 4</div>
          {MOCK.bills.map((b) => (
            <div key={b.id} style={{ padding: '10px 16px', borderBottom: `1px solid ${th.line}`, display: 'flex', justifyContent: 'space-between', fontFamily: th.mono, fontSize: 11 }}>
              <div>
                <div style={{ fontFamily: th.body, fontSize: 12, fontWeight: 500 }}>{b.name}</div>
                <div style={{ color: th.muted, fontSize: 10, marginTop: 2 }}>{b.dueDate.toUpperCase()} · {b.dueIn}</div>
              </div>
              <div style={{ fontWeight: 600 }}>{fmtMoneyShort(b.amount, th.currency)}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 04 · Magazine — feature spread with image blocks
// ─────────────────────────────────────────────────────────────
function WebMagazine({ th }) {
  return (
    <div style={{ height: WEB_H, background: th.paper, color: th.ink, fontFamily: th.body, overflow: 'hidden', display: 'flex' }}>
      {/* Left — feature panel */}
      <div style={{ width: 460, background: th.ink, color: th.paper, padding: 36, display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
        <div>
          <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 2, opacity: 0.5, marginBottom: 14 }}>ISSUE 24 · MAY 2026</div>
          <div style={{ fontFamily: th.display, fontSize: 56, lineHeight: 1, letterSpacing: -1.6, marginBottom: 18 }}>
            A quiet month.
          </div>
          <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 18, opacity: 0.7, lineHeight: 1.35 }}>
            You spent 8.4% less than April. Most of the savings came from Shopping and Entertainment.
          </div>
        </div>
        <div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 18, paddingBottom: 16, borderBottom: `1px solid rgba(255,255,255,0.15)` }}>
            <div>
              <div style={{ fontSize: 10, opacity: 0.5, letterSpacing: 1.5, textTransform: 'uppercase' }}>Net Worth</div>
              <div style={{ fontFamily: th.display, fontSize: 36, letterSpacing: -1, marginTop: 4 }}>{fmtMoneyShort(MOCK.balance + 21430, th.currency)}</div>
            </div>
            <div>
              <div style={{ fontSize: 10, opacity: 0.5, letterSpacing: 1.5, textTransform: 'uppercase' }}>Saved</div>
              <div style={{ fontFamily: th.display, fontSize: 36, letterSpacing: -1, marginTop: 4, color: th.accent2 }}>{fmtMoneyShort(3362, th.currency)}</div>
            </div>
          </div>
          <div style={{ paddingTop: 18, display: 'flex', alignItems: 'center', gap: 12 }}>
            <MerchantGlyph name="A" size={36} bg={th.accent} fg="#fff"/>
            <div style={{ fontSize: 12, opacity: 0.8 }}>
              <div style={{ fontWeight: 500 }}>Alex Morgan</div>
              <div style={{ opacity: 0.6 }}>Personal report · Generated 9:41 AM</div>
            </div>
          </div>
        </div>
      </div>

      {/* Right — feature content */}
      <div style={{ flex: 1, padding: 36, overflowY: 'auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 26 }}>
          <div style={{ display: 'flex', gap: 24, fontFamily: th.mono, fontSize: 11, letterSpacing: 1.5, textTransform: 'uppercase', color: th.muted }}>
            <span style={{ color: th.ink, fontWeight: 600 }}>Overview</span>
            <span>Detail</span>
            <span>Plan</span>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="search" size={14}/></div>
            <div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="bell" size={14}/></div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '0 14px', height: 36, borderRadius: 18, background: th.accent, color: '#fff', fontSize: 13, fontWeight: 500 }}><Icon name="plus" size={14} stroke={2}/>Add</div>
          </div>
        </div>

        {/* Two-column feature grid */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20, marginBottom: 24 }}>
          {/* Big chart card */}
          <div style={{ gridColumn: 'span 2', background: th.card, border: `1px solid ${th.line}`, borderRadius: 16, padding: 24 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 18 }}>
              <div>
                <div style={{ fontFamily: th.display, fontSize: 22, fontStyle: 'italic', letterSpacing: -0.2 }}>The Story of May</div>
                <div style={{ fontSize: 12, color: th.muted, marginTop: 2 }}>Income vs. Spending, last 5 months</div>
              </div>
              <div style={{ display: 'flex', gap: 16, fontSize: 11 }}>
                <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}><span style={{ width: 10, height: 2, background: th.pos }}/>Income</span>
                <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}><span style={{ width: 10, height: 2, background: th.accent }}/>Spending</span>
              </div>
            </div>
            <AreaChart series={[MOCK.cashflow.map(c => c.inc), MOCK.cashflow.map(c => c.exp)]} width={680} height={130} colors={[th.pos, th.accent]} smooth/>
          </div>

          {/* Top category */}
          <div style={{ background: th.accent, color: '#fff', borderRadius: 16, padding: 24 }}>
            <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, opacity: 0.7, marginBottom: 6 }}>TOP CATEGORY</div>
            <div style={{ fontFamily: th.display, fontSize: 32, letterSpacing: -0.5, marginBottom: 8 }}>Housing</div>
            <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 14, opacity: 0.85, marginBottom: 24 }}>76% of fixed costs</div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 12 }}>
              <div style={{ fontFamily: th.display, fontSize: 44, lineHeight: 1, letterSpacing: -1.5 }}>{fmtMoneyShort(1850, th.currency)}</div>
              <div style={{ opacity: 0.75, fontSize: 12 }}>/ {fmtMoneyShort(1850, th.currency)} budget</div>
            </div>
          </div>

          {/* Savings goal */}
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 16, padding: 24 }}>
            <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, marginBottom: 6 }}>GOAL · ON TRACK</div>
            <div style={{ fontFamily: th.display, fontSize: 22, letterSpacing: -0.3, marginBottom: 4 }}>Japan trip</div>
            <div style={{ fontSize: 12, color: th.muted, marginBottom: 18 }}>ETA Mar 2027</div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
              <Ring value={2140} max={4500} size={64} stroke={6} color={th.accent} track={th.paperAlt}>
                <span style={{ fontFamily: th.mono, fontSize: 12, fontWeight: 600 }}>48%</span>
              </Ring>
              <div>
                <div style={{ fontFamily: th.display, fontSize: 24, letterSpacing: -0.5 }}>{fmtMoney(2140, th.currency)}</div>
                <div style={{ fontSize: 11, color: th.muted, marginTop: 2 }}>of {fmtMoneyShort(4500, th.currency)}</div>
              </div>
            </div>
          </div>
        </div>

        {/* Pull quote / recent activity */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
          <div style={{ borderTop: `0.5px solid ${th.line}`, paddingTop: 16 }}>
            <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, marginBottom: 10 }}>NOTABLE THIS WEEK</div>
            {MOCK.transactions.slice(0, 4).map((tx) => (
              <div key={tx.id} style={{ display: 'flex', padding: '8px 0', borderBottom: `0.5px dotted ${th.line}`, alignItems: 'baseline', gap: 12 }}>
                <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, width: 36, flexShrink: 0 }}>{tx.date.slice(5)}</div>
                <div style={{ flex: 1, minWidth: 0, fontSize: 13 }}>{tx.merchant}</div>
                <div style={{ fontFamily: th.mono, fontSize: 11, fontWeight: 500, color: tx.amount > 0 ? th.pos : th.ink }}>{tx.amount > 0 ? '+' : ''}{fmtMoneyShort(tx.amount, th.currency)}</div>
              </div>
            ))}
          </div>
          <div style={{ borderTop: `0.5px solid ${th.line}`, paddingTop: 16 }}>
            <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, marginBottom: 10 }}>UPCOMING</div>
            {MOCK.bills.slice(0, 4).map((b) => (
              <div key={b.id} style={{ display: 'flex', padding: '8px 0', borderBottom: `0.5px dotted ${th.line}`, alignItems: 'baseline', gap: 12 }}>
                <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, width: 36, flexShrink: 0 }}>{b.dueDate.slice(0, 6)}</div>
                <div style={{ flex: 1, minWidth: 0, fontSize: 13 }}>{b.name}</div>
                <div style={{ fontFamily: th.mono, fontSize: 11, fontWeight: 500 }}>{fmtMoneyShort(b.amount, th.currency)}</div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 05 · Timeline — vertical chronological rail
// ─────────────────────────────────────────────────────────────
function WebTimeline({ th }) {
  // Group transactions by date
  const groups = {};
  MOCK.transactions.forEach((tx) => { (groups[tx.date] = groups[tx.date] || []).push(tx); });
  const dates = Object.keys(groups).sort().reverse();

  return (
    <div style={{ height: WEB_H, background: th.paper, color: th.ink, fontFamily: th.body, display: 'flex', overflow: 'hidden' }}>
      <WebSidebar th={th} active="tx" collapsed/>
      <div style={{ flex: 1, display: 'flex', minWidth: 0 }}>
        {/* Timeline rail */}
        <div style={{ flex: 1, overflowY: 'auto', padding: '32px 40px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 28 }}>
            <div>
              <div style={{ fontFamily: th.display, fontSize: 32, letterSpacing: -0.6 }}>Activity</div>
              <div style={{ fontSize: 13, color: th.muted, marginTop: 4 }}>16 transactions · May 2026</div>
            </div>
            <div style={{ display: 'flex', gap: 8 }}>
              <div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.paperAlt, borderRadius: 18, fontSize: 13 }}><Icon name="filter" size={14}/>All accounts</div>
              <div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.paperAlt, borderRadius: 18, fontSize: 13 }}><Icon name="calendar" size={14}/>May 2026</div>
            </div>
          </div>

          {/* Days */}
          {dates.slice(0, 6).map((d) => {
            const dayTotal = groups[d].reduce((s, t) => s + t.amount, 0);
            return (
              <div key={d} style={{ marginBottom: 24, display: 'grid', gridTemplateColumns: '80px 1fr', gap: 24 }}>
                <div style={{ position: 'sticky', top: 0, paddingTop: 6 }}>
                  <div style={{ fontFamily: th.display, fontSize: 36, lineHeight: 1, letterSpacing: -0.5 }}>{parseInt(d.slice(-2))}</div>
                  <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1, color: th.muted, marginTop: 4 }}>MAY</div>
                  <div style={{ fontSize: 11, color: th.muted, marginTop: 12 }}>{groups[d].length} item{groups[d].length > 1 ? 's' : ''}</div>
                  <div style={{ fontFamily: th.mono, fontSize: 12, fontWeight: 600, marginTop: 2 }}>{dayTotal > 0 ? '+' : ''}{fmtMoneyShort(dayTotal, th.currency)}</div>
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 0, borderLeft: `1px solid ${th.line}`, paddingLeft: 24 }}>
                  {groups[d].map((tx, i) => {
                    const cat = catById(tx.category);
                    const inc = tx.amount > 0;
                    return (
                      <div key={tx.id} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '12px 0', borderBottom: i < groups[d].length - 1 ? `0.5px solid ${th.line}` : 'none', position: 'relative' }}>
                        <span style={{ position: 'absolute', left: -28, width: 9, height: 9, borderRadius: 5, background: th.paper, border: `1.5px solid ${inc ? th.pos : th.accent}` }}/>
                        <MerchantGlyph name={tx.merchant} size={36} hue={cat.hue}/>
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{ fontSize: 14, fontWeight: 500 }}>{tx.merchant}</div>
                          <div style={{ fontSize: 11, color: th.muted, marginTop: 2 }}>
                            {tx.time} · {cat.name || 'Income'} · {acctById(tx.account).name}
                            {tx.recurring && <span style={{ marginLeft: 6, color: th.accent }}>· recurring</span>}
                            {tx.pending && <span style={{ marginLeft: 6, color: th.warn }}>· pending</span>}
                          </div>
                        </div>
                        <div style={{ fontFamily: th.body, fontSize: 14, fontWeight: 500, color: inc ? th.pos : th.ink, fontVariantNumeric: 'tabular-nums' }}>
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

        {/* Right rail */}
        <div style={{ width: 320, borderLeft: `1px solid ${th.line}`, padding: 28, background: th.paperAlt, overflowY: 'auto' }}>
          <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, marginBottom: 10 }}>MONTH AT A GLANCE</div>
          <div style={{ fontFamily: th.display, fontSize: 40, letterSpacing: -1, lineHeight: 1, marginBottom: 4 }}>{fmtMoneyShort(MOCK.monthSpent, th.currency)}</div>
          <div style={{ fontSize: 12, color: th.pos, marginBottom: 24 }}>↓ 8.4% vs April</div>

          <Sparkline values={MOCK.daily} width={264} height={50} color={th.accent} stroke={1.5}/>

          <div style={{ height: 1, background: th.line, margin: '20px 0' }}/>
          <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, marginBottom: 12 }}>TOP MERCHANTS</div>
          {[
            { n: 'Rent · Greene St.', v: 1850 },
            { n: 'IKEA',              v: 183 },
            { n: 'Apple',             v: 129 },
            { n: 'Whole Foods',       v: 84  },
          ].map((m) => (
            <div key={m.n} style={{ display: 'flex', justifyContent: 'space-between', padding: '8px 0', fontSize: 13, borderBottom: `0.5px dotted ${th.line}` }}>
              <span>{m.n}</span>
              <span style={{ fontFamily: th.mono, fontWeight: 500 }}>{fmtMoneyShort(m.v, th.currency)}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 06 · Insights-first — large chart hero + small cards
// ─────────────────────────────────────────────────────────────
function WebInsights({ th }) {
  const heroValues = MOCK.monthly.map(m => m.v);
  return (
    <div style={{ height: WEB_H, background: th.paper, color: th.ink, fontFamily: th.body, display: 'flex', overflow: 'hidden' }}>
      <WebSidebar th={th} active="insights"/>
      <div style={{ flex: 1, padding: '28px 36px', overflowY: 'auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 6 }}>
          <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.5 }}>Insights</div>
          <div style={{ display: 'flex', gap: 4, padding: 4, background: th.paperAlt, borderRadius: 10 }}>
            {['Spending','Income','Net Worth','Cashflow'].map((t, i) => (
              <div key={t} style={{ padding: '6px 14px', fontSize: 12, fontWeight: 500, borderRadius: 6, background: i === 0 ? th.card : 'transparent', color: i === 0 ? th.ink : th.muted, boxShadow: i === 0 ? '0 1px 2px rgba(0,0,0,0.05)' : 'none' }}>{t}</div>
            ))}
          </div>
        </div>
        <div style={{ fontSize: 13, color: th.muted, marginBottom: 28 }}>Compare months, spot patterns, find waste.</div>

        {/* Hero chart */}
        <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 16, padding: 28, marginBottom: 20 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 }}>
            <div>
              <div style={{ fontSize: 12, color: th.muted, letterSpacing: 0.5, marginBottom: 6 }}>Monthly spending · 12 months</div>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 16 }}>
                <div style={{ fontFamily: th.display, fontSize: 56, letterSpacing: -1.8, lineHeight: 1 }}>{fmtMoneyShort(MOCK.monthSpent, th.currency)}</div>
                <div style={{ fontSize: 14, color: th.pos, fontWeight: 500 }}>↓ 8.4% MoM · ↓ 13.2% YoY</div>
              </div>
            </div>
            <div style={{ display: 'flex', gap: 6 }}>
              {['1M','3M','6M','1Y','All'].map((p) => (
                <div key={p} style={{ padding: '6px 12px', fontSize: 12, borderRadius: 6, background: p === '1Y' ? th.ink : 'transparent', color: p === '1Y' ? th.paper : th.muted }}>{p}</div>
              ))}
            </div>
          </div>
          <BarChart values={heroValues} labels={MOCK.monthly.map(m => m.m)} width={1040} height={180} color={th.muted} highlight={th.accent} muted={th.paperAlt}/>
        </div>

        {/* Insight cards */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 16 }}>
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 22 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 14 }}>
              <div style={{ width: 32, height: 32, borderRadius: 16, background: `${th.accent}1a`, color: th.accent, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="arrow-d" size={16}/></div>
              <div style={{ fontSize: 12, color: th.muted, fontWeight: 500, letterSpacing: 0.4 }}>Biggest drop</div>
            </div>
            <div style={{ fontFamily: th.display, fontSize: 22, letterSpacing: -0.3, marginBottom: 4 }}>Entertainment</div>
            <div style={{ fontSize: 13, color: th.ink2, lineHeight: 1.45 }}>From <Money value={342} currency={th.currency}/> in April to just <Money value={98.40} currency={th.currency}/> — your lowest in 9 months.</div>
          </div>
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 22 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 14 }}>
              <div style={{ width: 32, height: 32, borderRadius: 16, background: `${th.warn}1a`, color: th.warn, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="arrow-u" size={16}/></div>
              <div style={{ fontSize: 12, color: th.muted, fontWeight: 500, letterSpacing: 0.4 }}>Watch out</div>
            </div>
            <div style={{ fontFamily: th.display, fontSize: 22, letterSpacing: -0.3, marginBottom: 4 }}>Shopping over budget</div>
            <div style={{ fontSize: 13, color: th.ink2, lineHeight: 1.45 }}>You've spent <Money value={312.18} currency={th.currency}/> of your <Money value={300} currency={th.currency}/> budget with a week to go.</div>
          </div>
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 22 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 14 }}>
              <div style={{ width: 32, height: 32, borderRadius: 16, background: `${th.pos}1a`, color: th.pos, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="sparkle" size={16}/></div>
              <div style={{ fontSize: 12, color: th.muted, fontWeight: 500, letterSpacing: 0.4 }}>Pattern</div>
            </div>
            <div style={{ fontFamily: th.display, fontSize: 22, letterSpacing: -0.3, marginBottom: 4 }}>Friday is your spendy day</div>
            <div style={{ fontSize: 13, color: th.ink2, lineHeight: 1.45 }}>You spend 2.3× more on Fridays than any other day. Mostly food & drinks.</div>
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { WebEditorial, WebClassic, WebSpreadsheet, WebMagazine, WebTimeline, WebInsights, WebSidebar, WebTopBar, WEB_W, WEB_H });
