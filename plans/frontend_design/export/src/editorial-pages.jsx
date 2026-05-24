// Editorial flow — extra screens.
// Adds:
//  - Web Mobile frame helper + section content (re-uses mobile screens)
//  - Web Desktop screens with consistent sidebar (Accounts/Budgets/Scheduled/Insights)
//  - Detail views (account drill-in, budget drill-in) for both mobile and desktop
//
// The sidebar matches the Classic-admin template so users get the same nav
// chrome regardless of which Editorial page they're on.

const WEB_MOBILE_W = 430;
const WEB_MOBILE_H = 900;

// ─────────────────────────────────────────────────────────────
// Shell — every Editorial desktop page is wrapped in this.
// Sidebar (left) + page header (top) + content (right). Active tab passed in.
// ─────────────────────────────────────────────────────────────
function WebShell({ th, active, title, sub, actions, children }) {
  return (
    <div style={{ height: WEB_H, background: th.paper, color: th.ink, fontFamily: th.body, display: 'flex', overflow: 'hidden' }}>
      <WebSidebar th={th} active={active}/>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '20px 32px', borderBottom: `1px solid ${th.line}` }}>
          <div>
            <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.6, lineHeight: 1, fontStyle: 'italic' }}>{title}</div>
            {sub && <div style={{ fontSize: 13, color: th.muted, marginTop: 4 }}>{sub}</div>}
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, height: 36, padding: '0 14px', background: th.paperAlt, borderRadius: 18, color: th.muted, fontSize: 13, width: 240 }}>
              <Icon name="search" size={14}/>Search…
            </div>
            <div style={{ width: 36, height: 36, borderRadius: 18, background: th.paperAlt, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="bell" size={16}/></div>
            {actions}
          </div>
        </div>
        <div style={{ flex: 1, overflowY: 'auto' }}>{children}</div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 1 · Accounts overview — cards + activity merged (like mobile)
// ─────────────────────────────────────────────────────────────
function WebAccountsOverview({ th }) {
  const total = MOCK.accounts.reduce((s, a) => s + a.balance, 0);
  return (
    <WebShell th={th} active="accts" title="Accounts" sub="4 linked · synced 9:41 AM"
      actions={<div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.ink, color: th.paper, borderRadius: 18, fontSize: 13, fontWeight: 500 }}><Icon name="plus" size={14} stroke={2}/>Link account</div>}>
      <div style={{ padding: 32 }}>
        {/* Hero — net worth + sparkline */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: 28, paddingBottom: 22, borderBottom: `1px solid ${th.line}` }}>
          <div>
            <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1.2, textTransform: 'uppercase' }}>Net worth · all accounts</div>
            <div style={{ fontFamily: th.display, fontSize: 64, letterSpacing: -2.4, lineHeight: 1, marginTop: 4 }}>
              <Money value={total} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
            </div>
            <div style={{ fontSize: 13, color: th.pos, marginTop: 8 }}>+ <Money value={812} currency={th.currency}/> this month · <span style={{ color: th.muted }}>+2.7%</span></div>
          </div>
          <Sparkline values={MOCK.daily.map((_, i) => 100 + i * 8 + Math.sin(i / 2) * 30)} width={360} height={84} color={th.accent} stroke={1.8}/>
        </div>

        {/* Account cards grid */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 16, marginBottom: 28 }}>
          {MOCK.accounts.map((a) => (
            <div key={a.id} style={{ background: a.color, color: '#fff', borderRadius: 16, padding: 24, position: 'relative', overflow: 'hidden' }}>
              <div style={{ position: 'absolute', top: -40, right: -60, width: 200, height: 200, borderRadius: 100, background: 'rgba(255,255,255,0.05)' }}/>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                <div>
                  <div style={{ fontSize: 11, opacity: 0.7, letterSpacing: 0.6, textTransform: 'uppercase' }}>{a.type}</div>
                  <div style={{ fontFamily: th.display, fontSize: 24, letterSpacing: -0.3, marginTop: 2 }}>{a.name}</div>
                </div>
                <div style={{ fontFamily: th.mono, fontSize: 11, opacity: 0.7 }}>•••• {a.last4}</div>
              </div>
              <div style={{ marginTop: 28, display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
                <div>
                  <div style={{ fontSize: 10, opacity: 0.6, letterSpacing: 1, marginBottom: 4 }}>BALANCE</div>
                  <div style={{ fontFamily: th.display, fontSize: 36, letterSpacing: -1, lineHeight: 1 }}>
                    {a.balance < 0 ? '−' : ''}<Money value={Math.abs(a.balance)} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
                  </div>
                </div>
                <span style={{ fontSize: 11, opacity: 0.65, padding: '4px 10px', background: 'rgba(255,255,255,0.12)', borderRadius: 12 }}>View →</span>
              </div>
            </div>
          ))}
        </div>

        {/* Activity merged */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 14 }}>
          <div style={{ fontFamily: th.display, fontSize: 22, fontStyle: 'italic', letterSpacing: -0.2 }}>Recent activity · all accounts</div>
          <div style={{ display: 'flex', gap: 8 }}>
            <div style={{ height: 32, padding: '0 12px', display: 'flex', alignItems: 'center', gap: 6, background: th.paperAlt, borderRadius: 16, fontSize: 12 }}><Icon name="filter" size={12}/>All accounts</div>
            <div style={{ height: 32, padding: '0 12px', display: 'flex', alignItems: 'center', gap: 6, background: th.paperAlt, borderRadius: 16, fontSize: 12 }}><Icon name="calendar" size={12}/>May 2026</div>
            <div style={{ height: 32, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.ink, color: th.paper, borderRadius: 16, fontSize: 12, fontWeight: 500 }}><Icon name="doc" size={12}/>Export</div>
          </div>
        </div>
        <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '90px 1fr 130px 130px 90px 130px', padding: '10px 18px', fontFamily: th.mono, fontSize: 9, letterSpacing: 1.5, color: th.muted, background: th.paperAlt, borderBottom: `1px solid ${th.line}` }}>
            <span>DATE</span><span>MERCHANT</span><span>CATEGORY</span><span>ACCOUNT</span><span>STATUS</span><span style={{ textAlign: 'right' }}>AMOUNT</span>
          </div>
          {MOCK.transactions.slice(0, 8).map((tx) => {
            const cat = catById(tx.category);
            const acct = acctById(tx.account);
            const inc = tx.amount > 0;
            return (
              <div key={tx.id} style={{ display: 'grid', gridTemplateColumns: '90px 1fr 130px 130px 90px 130px', padding: '12px 18px', alignItems: 'center', borderBottom: `0.5px solid ${th.line}`, fontSize: 13 }}>
                <span style={{ fontFamily: th.mono, color: th.muted, fontSize: 11 }}>{tx.date.slice(5).replace('-','/')}</span>
                <span style={{ display: 'flex', alignItems: 'center', gap: 10, fontWeight: 500 }}>
                  <MerchantGlyph name={tx.merchant} size={26} hue={cat.hue}/>{tx.merchant}
                </span>
                <span style={{ color: th.ink2, fontSize: 12, display: 'flex', alignItems: 'center', gap: 6 }}><CatDot hue={cat.hue}/>{cat.name || 'Income'}</span>
                <span style={{ color: th.muted, fontSize: 12 }}>{acct.name}</span>
                <span style={{ fontFamily: th.mono, fontSize: 10, color: tx.pending ? th.warn : th.muted }}>{tx.pending ? 'PENDING' : 'POSTED'}</span>
                <span style={{ textAlign: 'right', fontFamily: th.mono, fontWeight: 600, color: inc ? th.pos : th.ink }}>{inc ? '+' : ''}{fmtMoney(tx.amount, th.currency)}</span>
              </div>
            );
          })}
        </div>
      </div>
    </WebShell>
  );
}

// ─────────────────────────────────────────────────────────────
// 1b · Account detail (drill-in) — one account, full history + chart
// ─────────────────────────────────────────────────────────────
function WebAccountDetail({ th }) {
  const a = MOCK.accounts[0]; // Chase Checking
  const txs = MOCK.transactions.filter((t) => t.account === a.id);
  return (
    <WebShell th={th} active="accts" title={a.name} sub={`•••• ${a.last4} · ${a.type}`}
      actions={<div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.paperAlt, borderRadius: 18, fontSize: 13 }}><Icon name="dots" size={14}/>More</div>}>
      <div style={{ padding: 32 }}>
        {/* Breadcrumb */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: th.muted, marginBottom: 18 }}>
          <span>Accounts</span><Icon name="chev" size={11}/><span style={{ color: th.ink }}>{a.name}</span>
        </div>

        {/* Hero balance card */}
        <div style={{ background: a.color, color: '#fff', borderRadius: 16, padding: 28, marginBottom: 24, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 32, position: 'relative', overflow: 'hidden' }}>
          <div style={{ position: 'absolute', top: -60, right: -80, width: 240, height: 240, borderRadius: 120, background: 'rgba(255,255,255,0.05)' }}/>
          <div>
            <div style={{ fontSize: 11, opacity: 0.65, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 6 }}>Available balance</div>
            <div style={{ fontFamily: th.display, fontSize: 56, letterSpacing: -2, lineHeight: 1 }}>
              <Money value={a.balance} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
            </div>
            <div style={{ display: 'flex', gap: 20, marginTop: 22 }}>
              <div><div style={{ fontSize: 10, opacity: 0.6, letterSpacing: 1, marginBottom: 3 }}>IN · 30D</div><div style={{ fontFamily: th.display, fontSize: 22 }}>{fmtMoneyShort(5800, th.currency)}</div></div>
              <div><div style={{ fontSize: 10, opacity: 0.6, letterSpacing: 1, marginBottom: 3 }}>OUT · 30D</div><div style={{ fontFamily: th.display, fontSize: 22 }}>{fmtMoneyShort(1850, th.currency)}</div></div>
              <div><div style={{ fontSize: 10, opacity: 0.6, letterSpacing: 1, marginBottom: 3 }}>NET</div><div style={{ fontFamily: th.display, fontSize: 22, color: '#9bb89b' }}>+{fmtMoneyShort(3950, th.currency)}</div></div>
            </div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', position: 'relative' }}>
            <Sparkline values={[3200,3400,3300,3700,3650,4100,4050,4300,4250,4400,4500,4450,4218]} width={420} height={120} color="#fff" stroke={1.8} fillOpacity={0.16}/>
          </div>
        </div>

        {/* Two-column lower */}
        <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: 16 }}>
          {/* Transactions table */}
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden' }}>
            <div style={{ padding: '14px 18px', borderBottom: `1px solid ${th.line}`, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div style={{ fontSize: 14, fontWeight: 600 }}>All transactions · {txs.length}</div>
              <div style={{ fontSize: 12, color: th.muted, display: 'flex', alignItems: 'center', gap: 4 }}><Icon name="filter" size={12}/>Filter</div>
            </div>
            {txs.slice(0, 6).map((tx, i) => {
              const cat = catById(tx.category);
              const inc = tx.amount > 0;
              return (
                <div key={tx.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 18px', borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
                  <MerchantGlyph name={tx.merchant} size={32} hue={cat.hue}/>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 13, fontWeight: 500 }}>{tx.merchant}</div>
                    <div style={{ fontSize: 11, color: th.muted, marginTop: 2 }}>{tx.date.slice(5).replace('-','/')} · {cat.name || 'Income'}</div>
                  </div>
                  <Money value={tx.amount} currency={th.currency} signed={inc} style={{ fontFamily: th.mono, fontSize: 13, fontWeight: 600, color: inc ? th.pos : th.ink }}/>
                </div>
              );
            })}
          </div>

          {/* Account details */}
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 18 }}>
            <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.2, color: th.muted, marginBottom: 10 }}>ACCOUNT DETAILS</div>
            {[
              ['Type', a.type.charAt(0).toUpperCase() + a.type.slice(1)],
              ['Number', `•••• ${a.last4}`],
              ['Routing', '021000021'],
              ['Institution', 'Chase Bank, N.A.'],
              ['Currency', th.currency],
              ['Last sync', '2 min ago'],
              ['Linked since', 'Jan 2024'],
            ].map(([l, v], i) => (
              <div key={l} style={{ display: 'flex', justifyContent: 'space-between', padding: '8px 0', borderTop: i ? `0.5px dotted ${th.line}` : 'none', fontSize: 12 }}>
                <span style={{ color: th.muted }}>{l}</span>
                <span style={{ fontFamily: th.mono }}>{v}</span>
              </div>
            ))}
            <div style={{ marginTop: 14, padding: '10px 14px', background: th.paperAlt, borderRadius: 8, fontSize: 12, color: th.ink2, display: 'flex', alignItems: 'center', gap: 8 }}>
              <Icon name="sync" size={12}/>Auto-categorize: on
            </div>
          </div>
        </div>
      </div>
    </WebShell>
  );
}

// ─────────────────────────────────────────────────────────────
// 2 · Budgets overview
// ─────────────────────────────────────────────────────────────
function WebBudgetsOverview({ th }) {
  const totalSpent = MOCK.categories.reduce((s, c) => s + c.spent, 0);
  const totalBudget = MOCK.categories.reduce((s, c) => s + c.budget, 0);
  const pct = (totalSpent / totalBudget) * 100;
  return (
    <WebShell th={th} active="budget" title="Budgets" sub="May 2026 · 7 days remaining"
      actions={<div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.ink, color: th.paper, borderRadius: 18, fontSize: 13, fontWeight: 500 }}><Icon name="edit" size={14}/>Edit budgets</div>}>
      <div style={{ padding: 32 }}>
        {/* Hero */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 16, marginBottom: 28 }}>
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 22, display: 'flex', alignItems: 'center', gap: 18 }}>
            <Ring value={totalSpent} max={totalBudget} size={88} stroke={9} color={th.accent} track={th.paperAlt}>
              <div style={{ textAlign: 'center' }}>
                <div style={{ fontFamily: th.display, fontSize: 22, letterSpacing: -0.4, lineHeight: 1 }}>{Math.round(pct)}%</div>
                <div style={{ fontSize: 8, color: th.muted, letterSpacing: 1, marginTop: 2 }}>USED</div>
              </div>
            </Ring>
            <div>
              <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1, textTransform: 'uppercase' }}>Total</div>
              <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.6, marginTop: 2 }}><Money value={totalSpent} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/></div>
              <div style={{ fontSize: 11, color: th.muted, marginTop: 2 }}>of <Money value={totalBudget} currency={th.currency}/></div>
            </div>
          </div>
          {[
            { l: 'On track',  v: 5, c: th.pos,  i: 'check' },
            { l: 'Over',      v: 1, c: th.neg,  i: 'arrow-u' },
          ].map((s) => (
            <div key={s.l} style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 22 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12 }}>
                <div style={{ width: 32, height: 32, borderRadius: 16, background: `${s.c}1a`, color: s.c, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name={s.i} size={16}/></div>
                <div style={{ fontSize: 12, color: th.muted, letterSpacing: 0.4 }}>{s.l}</div>
              </div>
              <div style={{ fontFamily: th.display, fontSize: 40, letterSpacing: -1, lineHeight: 1 }}>{s.v}</div>
              <div style={{ fontSize: 12, color: th.muted, marginTop: 6 }}>{s.l === 'Over' ? 'Shopping needs attention' : 'Categories within plan'}</div>
            </div>
          ))}
        </div>

        {/* Per-category */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 12 }}>
          <div style={{ fontFamily: th.display, fontSize: 22, fontStyle: 'italic' }}>Categories</div>
          <span style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1 }}>SPENT / BUDGET · MAY</span>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          {MOCK.categories.map((c) => {
            const cpct = (c.spent / c.budget) * 100;
            const over = cpct > 100;
            const remaining = c.budget - c.spent;
            return (
              <div key={c.id} style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 18, display: 'flex', alignItems: 'center', gap: 16 }}>
                <div style={{ width: 44, height: 44, borderRadius: 22, background: `oklch(0.92 0.04 ${c.hue})`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, flexShrink: 0 }}>
                  <Icon name={c.icon} size={20}/>
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                    <div style={{ fontSize: 14, fontWeight: 600 }}>{c.name}</div>
                    <div style={{ fontFamily: th.mono, fontSize: 12, color: over ? th.neg : th.ink }}>
                      {fmtMoneyShort(c.spent, th.currency)} / {fmtMoneyShort(c.budget, th.currency)}
                    </div>
                  </div>
                  <div style={{ height: 4, background: th.paperAlt, borderRadius: 2, overflow: 'hidden', marginTop: 8 }}>
                    <div style={{ width: `${Math.min(cpct, 100)}%`, height: '100%', background: over ? th.neg : th.accent }}/>
                  </div>
                  <div style={{ fontSize: 11, color: over ? th.neg : th.muted, marginTop: 6 }}>
                    {over ? `${fmtMoneyShort(-remaining, th.currency)} over · drop pace` : `${fmtMoneyShort(remaining, th.currency)} left · ${Math.round((c.spent / 24) * 30 / c.budget * 100)}% pace`}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </WebShell>
  );
}

// ─────────────────────────────────────────────────────────────
// 2b · Budget detail — drill into a single category
// ─────────────────────────────────────────────────────────────
function WebBudgetDetail({ th }) {
  const c = MOCK.categories[0]; // Food & Dining
  const cTxs = MOCK.transactions.filter((t) => t.category === c.id);
  const cpct = (c.spent / c.budget) * 100;
  return (
    <WebShell th={th} active="budget" title={c.name} sub="May 2026 budget"
      actions={<div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.paperAlt, borderRadius: 18, fontSize: 13 }}><Icon name="edit" size={14}/>Edit</div>}>
      <div style={{ padding: 32 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: th.muted, marginBottom: 18 }}>
          <span>Budgets</span><Icon name="chev" size={11}/><span style={{ color: th.ink }}>{c.name}</span>
        </div>

        {/* Hero ring + summary */}
        <div style={{ display: 'grid', gridTemplateColumns: '320px 1fr', gap: 20, marginBottom: 28 }}>
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 16, padding: 26, display: 'flex', alignItems: 'center', gap: 22 }}>
            <Ring value={c.spent} max={c.budget} size={130} stroke={11} color={th.accent} track={th.paperAlt}>
              <div style={{ textAlign: 'center' }}>
                <div style={{ fontFamily: th.display, fontSize: 30, letterSpacing: -0.6, lineHeight: 1 }}>{Math.round(cpct)}%</div>
                <div style={{ fontSize: 9, color: th.muted, letterSpacing: 1, marginTop: 2 }}>USED</div>
              </div>
            </Ring>
            <div>
              <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.6, lineHeight: 1 }}>
                <Money value={c.spent} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
              </div>
              <div style={{ fontSize: 12, color: th.muted, marginTop: 4 }}>of <Money value={c.budget} currency={th.currency}/></div>
              <div style={{ fontSize: 12, color: th.pos, marginTop: 8, fontWeight: 500 }}>{fmtMoneyShort(c.budget - c.spent, th.currency)} remaining</div>
            </div>
          </div>
          {/* Last 6 months */}
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 16, padding: 22 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 14 }}>
              <div style={{ fontSize: 13, fontWeight: 600 }}>6-month history</div>
              <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.8 }}>AVG · {fmtMoneyShort(680, th.currency)}</div>
            </div>
            <BarChart values={[820,740,690,720,612,580].reverse()} labels={['Dec','Jan','Feb','Mar','Apr','May']} width={600} height={140} color={th.muted} highlight={th.accent} muted={th.paperAlt}/>
          </div>
        </div>

        {/* Two-col bottom */}
        <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: 16 }}>
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14 }}>
            <div style={{ padding: '14px 18px', borderBottom: `1px solid ${th.line}`, fontSize: 14, fontWeight: 600 }}>Transactions · {cTxs.length}</div>
            {cTxs.map((tx, i) => (
              <div key={tx.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 18px', borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
                <MerchantGlyph name={tx.merchant} size={30} hue={c.hue}/>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 13, fontWeight: 500 }}>{tx.merchant}</div>
                  <div style={{ fontSize: 11, color: th.muted }}>{tx.date.slice(5).replace('-','/')} · {acctById(tx.account).name}</div>
                </div>
                <Money value={tx.amount} currency={th.currency} style={{ fontFamily: th.mono, fontSize: 13, fontWeight: 600 }}/>
              </div>
            ))}
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
            <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 18 }}>
              <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1.2, marginBottom: 10 }}>TOP MERCHANTS</div>
              {[['Whole Foods', 84], ['Trader Joe\u2019s', 42], ['Blue Bottle', 31], ['Pret', 14]].map(([n, v]) => (
                <div key={n} style={{ display: 'flex', justifyContent: 'space-between', padding: '7px 0', fontSize: 12, borderTop: `0.5px dotted ${th.line}` }}>
                  <span>{n}</span><span style={{ fontFamily: th.mono, fontWeight: 500 }}>{fmtMoneyShort(v, th.currency)}</span>
                </div>
              ))}
            </div>
            <div style={{ background: `${th.accent}1a`, color: th.accent, border: `1px solid ${th.accent}40`, borderRadius: 14, padding: 18 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}><Icon name="sparkle" size={14}/><span style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.2 }}>INSIGHT</span></div>
              <div style={{ fontSize: 13, lineHeight: 1.4 }}>You're <b>spending less on food</b> than any of the last 5 months. Keep it up.</div>
            </div>
          </div>
        </div>
      </div>
    </WebShell>
  );
}

// ─────────────────────────────────────────────────────────────
// 3 · Scheduled overview — big calendar + list
// ─────────────────────────────────────────────────────────────
function WebScheduledOverview({ th }) {
  const events = {
    14:[{label:'NYT',c:th.warn}], 15:[{label:'Rent',c:th.accent}], 19:[{label:'Netflix',c:th.warn}],
    22:[{label:'Spotify',c:th.warn},{label:'Payday',c:th.pos}], 30:[{label:'ConEd',c:th.accent}],
    // June overflow shown in next page
  };
  const days = [];
  for (let i = 0; i < 4; i++) days.push(null);
  for (let i = 1; i <= 31; i++) days.push(i);
  while (days.length % 7) days.push(null);

  return (
    <WebShell th={th} active="bills" title="Scheduled" sub="Bills, subscriptions, income · next 30 days"
      actions={<div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.ink, color: th.paper, borderRadius: 18, fontSize: 13, fontWeight: 500 }}><Icon name="plus" size={14} stroke={2}/>Add scheduled</div>}>
      <div style={{ padding: 32, display: 'grid', gridTemplateColumns: '1.6fr 1fr', gap: 24 }}>
        {/* Calendar */}
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: 16 }}>
            <div>
              <div style={{ fontFamily: th.display, fontSize: 36, letterSpacing: -0.8, lineHeight: 1 }}>May 2026</div>
              <div style={{ fontSize: 12, color: th.muted, marginTop: 4 }}>Week 21 · 7 events</div>
            </div>
            <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
              <div style={{ width: 32, height: 32, borderRadius: 16, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.muted }}><Icon name="chev-l" size={14}/></div>
              <div style={{ width: 32, height: 32, borderRadius: 16, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="chev" size={14}/></div>
              <div style={{ display: 'flex', gap: 2, padding: 3, background: th.paperAlt, borderRadius: 8, marginLeft: 8 }}>
                {['Month','Week','List'].map((t, i) => (
                  <div key={t} style={{ padding: '5px 10px', borderRadius: 5, fontSize: 11, fontWeight: 500, background: i === 0 ? th.card : 'transparent', color: i === 0 ? th.ink : th.muted, boxShadow: i === 0 ? '0 1px 2px rgba(0,0,0,0.05)' : 'none' }}>{t}</div>
                ))}
              </div>
            </div>
          </div>
          {/* Day headers */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7,1fr)', gap: 6, marginBottom: 6 }}>
            {['MON','TUE','WED','THU','FRI','SAT','SUN'].map((d, i) => (
              <div key={i} style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1, padding: '4px 6px' }}>{d}</div>
            ))}
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7,1fr)', gap: 6 }}>
            {days.map((d, i) => {
              if (!d) return <div key={i} style={{ aspectRatio: '1.1', background: th.paperAlt, borderRadius: 6, opacity: 0.4 }}/>;
              const evs = events[d] || [];
              const isToday = d === 24;
              return (
                <div key={i} style={{
                  aspectRatio: '1.1', padding: 6, borderRadius: 6,
                  background: isToday ? th.ink : th.card,
                  color: isToday ? th.paper : th.ink,
                  border: `0.5px solid ${isToday ? th.ink : th.line}`,
                  display: 'flex', flexDirection: 'column', gap: 3, overflow: 'hidden',
                }}>
                  <div style={{ fontSize: 12, fontWeight: 500, lineHeight: 1, opacity: isToday ? 1 : (d < 24 ? 0.5 : 1) }}>{d}</div>
                  {evs.map((e, j) => (
                    <div key={j} style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 10, padding: '2px 4px', borderRadius: 3, background: isToday ? 'rgba(255,255,255,0.1)' : `${e.c}1a`, color: isToday ? th.paper : e.c, fontWeight: 500 }}>
                      <span style={{ width: 5, height: 5, borderRadius: 3, background: e.c, flexShrink: 0 }}/>
                      <span style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{e.label}</span>
                    </div>
                  ))}
                </div>
              );
            })}
          </div>
          <div style={{ display: 'flex', gap: 18, marginTop: 18, fontSize: 11 }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}><span style={{ width: 8, height: 8, borderRadius: 4, background: th.accent }}/>Bill</span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}><span style={{ width: 8, height: 8, borderRadius: 4, background: th.warn }}/>Subscription</span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}><span style={{ width: 8, height: 8, borderRadius: 4, background: th.pos }}/>Income</span>
          </div>
        </div>

        {/* Right rail */}
        <div>
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 16, padding: 24, marginBottom: 16 }}>
            <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1.2, marginBottom: 6 }}>OUTFLOWS · NEXT 30D</div>
            <div style={{ fontFamily: th.display, fontSize: 38, letterSpacing: -1.2, lineHeight: 1 }}><Money value={2858.98} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/></div>
            <div style={{ fontSize: 12, color: th.muted, marginTop: 6 }}>+ <Money value={2900} currency={th.currency}/> coming in · net <span style={{ color: th.pos, fontWeight: 500 }}>+ <Money value={41} currency={th.currency}/></span></div>
          </div>
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 16, padding: 24 }}>
            <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic', marginBottom: 14 }}>Upcoming</div>
            {[
              { d:'May 30', label:'ConEd Electric',  amount:-84,   type:'Bill',  c:th.accent },
              { d:'Jun  4', label:'Verizon Fios',    amount:-69,   type:'Bill',  c:th.accent },
              { d:'Jun  5', label:'Payday',           amount:2900,  type:'Income',c:th.pos },
              { d:'Jun  7', label:'Amex Gold',       amount:-842,  type:'Bill',  c:th.accent },
              { d:'Jun  8', label:'iCloud+',         amount:-9.99, type:'Sub',   c:th.warn },
            ].map((u) => (
              <div key={u.label} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 0', borderTop: `0.5px solid ${th.line}` }}>
                <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 0.8, color: th.muted, width: 56, flexShrink: 0 }}>{u.d}</div>
                <span style={{ width: 6, height: 6, borderRadius: 3, background: u.c, flexShrink: 0 }}/>
                <div style={{ flex: 1, fontSize: 13 }}>{u.label}</div>
                <Money value={u.amount} currency={th.currency} signed={u.amount > 0} style={{ fontFamily: th.mono, fontSize: 12, fontWeight: 600, color: u.amount > 0 ? th.pos : th.ink }}/>
              </div>
            ))}
          </div>
        </div>
      </div>
    </WebShell>
  );
}

// ─────────────────────────────────────────────────────────────
// 4 · Insights overview — wraps the existing WebInsights body in shell
// (already uses sidebar, so just reuse)
// ─────────────────────────────────────────────────────────────
function WebInsightsOverview({ th }) {
  return <WebInsights th={th}/>;
}

// ─────────────────────────────────────────────────────────────
// Mobile detail screens — account drill-in + budget drill-in
// ─────────────────────────────────────────────────────────────
function ScreenAccountDetail({ th }) {
  const a = MOCK.accounts[0];
  const txs = MOCK.transactions.filter((t) => t.account === a.id);
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <div style={{ paddingTop: STATUS_PAD + 8 }}>
          <ScreenHeader th={th} title={a.name} back={true} trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="dots" size={16}/></div>}/>
        </div>

        {/* Hero card */}
        <div style={{ margin: '0 20px 18px', background: a.color, color: '#fff', borderRadius: 16, padding: 22, position: 'relative', overflow: 'hidden' }}>
          <div style={{ position: 'absolute', top: -40, right: -50, width: 180, height: 180, borderRadius: 90, background: 'rgba(255,255,255,0.06)' }}/>
          <div style={{ fontSize: 11, opacity: 0.65, letterSpacing: 1, textTransform: 'uppercase' }}>Available</div>
          <div style={{ fontFamily: th.display, fontSize: 44, letterSpacing: -1.6, lineHeight: 1, marginTop: 4 }}>
            <Money value={a.balance} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
          </div>
          <div style={{ fontFamily: th.mono, fontSize: 10, opacity: 0.65, letterSpacing: 0.6, marginTop: 6 }}>•••• {a.last4} · {a.type.toUpperCase()}</div>
          <Sparkline values={[3200,3400,3300,3700,3650,4100,4218]} width={320} height={48} color="#fff" stroke={1.5} fillOpacity={0.16}/>
        </div>

        {/* Quick actions */}
        <div style={{ padding: '0 20px 18px', display: 'flex', gap: 8 }}>
          {[
            { i: 'arrow-ur', l: 'Send' },
            { i: 'arrow-dl', l: 'Receive' },
            { i: 'doc',      l: 'Statement' },
            { i: 'cog',      l: 'Manage' },
          ].map((a) => (
            <div key={a.l} style={{ flex: 1, padding: '12px 0', borderRadius: 12, border: `1px solid ${th.line}`, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
              <Icon name={a.i} size={16}/>
              <span style={{ fontSize: 10, fontWeight: 500 }}>{a.l}</span>
            </div>
          ))}
        </div>

        {/* Transactions */}
        <div style={{ padding: '0 20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8 }}>
            <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic' }}>Transactions</div>
            <span style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.8 }}>{txs.length} · MAY</span>
          </div>
          {txs.map((tx, i) => {
            const cat = catById(tx.category);
            const inc = tx.amount > 0;
            return (
              <div key={tx.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 0', borderTop: `0.5px solid ${th.line}` }}>
                <MerchantGlyph name={tx.merchant} size={32} hue={cat.hue}/>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14, fontWeight: 500 }}>{tx.merchant}</div>
                  <div style={{ fontSize: 11, color: th.muted, marginTop: 1 }}>{tx.date.slice(5).replace('-','/')} · {cat.name || 'Income'}</div>
                </div>
                <Money value={tx.amount} currency={th.currency} signed={inc} style={{ fontSize: 13, fontWeight: 500, color: inc ? th.pos : th.ink }}/>
              </div>
            );
          })}
        </div>
      </div>
      <MobileTabBar th={th} active="accounts"/>
    </div>
  );
}

function ScreenBudgetDetail({ th }) {
  const c = MOCK.categories[0];
  const cTxs = MOCK.transactions.filter((t) => t.category === c.id);
  const cpct = (c.spent / c.budget) * 100;
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <div style={{ paddingTop: STATUS_PAD + 8 }}>
          <ScreenHeader th={th} title={c.name} back={true} trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="edit" size={14}/></div>}/>
        </div>

        {/* Ring + history */}
        <div style={{ padding: '0 24px 22px', display: 'flex', alignItems: 'center', gap: 22 }}>
          <Ring value={c.spent} max={c.budget} size={110} stroke={10} color={th.accent} track={th.paperAlt}>
            <div style={{ textAlign: 'center' }}>
              <div style={{ fontFamily: th.display, fontSize: 26, letterSpacing: -0.5, lineHeight: 1 }}>{Math.round(cpct)}%</div>
            </div>
          </Ring>
          <div>
            <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1, textTransform: 'uppercase' }}>Spent</div>
            <div style={{ fontFamily: th.display, fontSize: 30, letterSpacing: -0.7, marginTop: 2 }}><Money value={c.spent} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/></div>
            <div style={{ fontSize: 12, color: th.muted, marginTop: 2 }}>of <Money value={c.budget} currency={th.currency}/></div>
            <div style={{ marginTop: 6, fontSize: 11, color: th.pos, fontWeight: 500 }}>{fmtMoneyShort(c.budget - c.spent, th.currency)} left for 7 days</div>
          </div>
        </div>

        {/* Mini history */}
        <div style={{ margin: '0 20px 18px', padding: 16, background: th.card, border: `1px solid ${th.line}`, borderRadius: 14 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8 }}>
            <div style={{ fontSize: 12, fontWeight: 600 }}>6 months</div>
            <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted }}>AVG · {fmtMoneyShort(680, th.currency)}</div>
          </div>
          <BarChart values={[820,740,690,720,612,580].reverse()} labels={['D','J','F','M','A','M']} width={310} height={70} color={th.muted} highlight={th.accent} muted={th.paperAlt}/>
        </div>

        {/* Transactions */}
        <div style={{ padding: '0 24px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8 }}>
            <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic' }}>This category</div>
            <span style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.8 }}>{cTxs.length} TXNS</span>
          </div>
          {cTxs.map((tx, i) => (
            <div key={tx.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '11px 0', borderTop: `0.5px solid ${th.line}` }}>
              <MerchantGlyph name={tx.merchant} size={28} hue={c.hue}/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 500 }}>{tx.merchant}</div>
                <div style={{ fontSize: 11, color: th.muted }}>{tx.date.slice(5).replace('-','/')}</div>
              </div>
              <Money value={tx.amount} currency={th.currency} style={{ fontSize: 13, fontWeight: 500 }}/>
            </div>
          ))}
        </div>
      </div>
      <MobileTabBar th={th} active="budgets"/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Optional · Activity (cross-account feed)
// ─────────────────────────────────────────────────────────────
function WebActivityOverview({ th }) {
  return (
    <WebShell th={th} active="activity" title="Activity" sub={`${MOCK.transactions.length} transactions · May 2026`}
      actions={<div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.ink, color: th.paper, borderRadius: 18, fontSize: 13, fontWeight: 500 }}><Icon name="doc" size={14}/>Export</div>}>
      <div style={{ padding: 32 }}>
        {/* Filters */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 22, flexWrap: 'wrap' }}>
          <div style={{ height: 32, padding: '0 12px', display: 'flex', alignItems: 'center', gap: 6, background: th.ink, color: th.paper, borderRadius: 16, fontSize: 12, fontWeight: 500 }}>All accounts</div>
          {['All categories','May','Posted only'].map((t) => (
            <div key={t} style={{ height: 32, padding: '0 12px', display: 'flex', alignItems: 'center', gap: 6, background: th.paperAlt, borderRadius: 16, fontSize: 12 }}>{t}<Icon name="chev-d" size={11}/></div>
          ))}
          <div style={{ flex: 1 }}/>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, height: 32, padding: '0 12px', background: th.paperAlt, borderRadius: 16, fontSize: 12, color: th.muted, width: 240 }}>
            <Icon name="search" size={12}/>Search activity…
          </div>
        </div>

        {/* Summary tiles */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 12, marginBottom: 22 }}>
          {[
            { l: 'Money out',  v: -MOCK.monthSpent, c: th.ink },
            { l: 'Money in',   v: MOCK.monthIncome,  c: th.pos },
            { l: 'Avg / day',  v: -MOCK.monthSpent / 24, c: th.ink },
            { l: 'Largest',    v: -1850, c: th.ink },
          ].map((s) => (
            <div key={s.l} style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 12, padding: 14 }}>
              <div style={{ fontSize: 11, color: th.muted, letterSpacing: 0.6, textTransform: 'uppercase' }}>{s.l}</div>
              <div style={{ fontFamily: th.display, fontSize: 24, letterSpacing: -0.5, marginTop: 4, color: s.c }}>
                <Money value={s.v} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
              </div>
            </div>
          ))}
        </div>

        {/* Big transactions table */}
        <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '80px 1fr 140px 160px 90px 130px', padding: '10px 18px', fontFamily: th.mono, fontSize: 9, letterSpacing: 1.5, color: th.muted, background: th.paperAlt, borderBottom: `1px solid ${th.line}` }}>
            <span>DATE</span><span>MERCHANT</span><span>CATEGORY</span><span>ACCOUNT</span><span>STATUS</span><span style={{ textAlign: 'right' }}>AMOUNT</span>
          </div>
          {MOCK.transactions.map((tx, i) => {
            const cat = catById(tx.category);
            const acct = acctById(tx.account);
            const inc = tx.amount > 0;
            return (
              <div key={tx.id} style={{ display: 'grid', gridTemplateColumns: '80px 1fr 140px 160px 90px 130px', padding: '11px 18px', alignItems: 'center', borderBottom: i < MOCK.transactions.length - 1 ? `0.5px solid ${th.line}` : 'none', fontSize: 13 }}>
                <span style={{ fontFamily: th.mono, color: th.muted, fontSize: 11 }}>{tx.date.slice(5).replace('-','/')}</span>
                <span style={{ display: 'flex', alignItems: 'center', gap: 10, fontWeight: 500 }}>
                  <MerchantGlyph name={tx.merchant} size={26} hue={cat.hue}/>{tx.merchant}
                  {tx.recurring && <span style={{ fontFamily: th.mono, fontSize: 9, letterSpacing: 0.6, color: th.muted, background: th.paperAlt, padding: '1px 6px', borderRadius: 4 }}>RECUR</span>}
                </span>
                <span style={{ color: th.ink2, fontSize: 12, display: 'flex', alignItems: 'center', gap: 6 }}><CatDot hue={cat.hue}/>{cat.name || 'Income'}</span>
                <span style={{ color: th.muted, fontSize: 12 }}>{acct.name}</span>
                <span style={{ fontFamily: th.mono, fontSize: 10, color: tx.pending ? th.warn : th.muted }}>{tx.pending ? 'PENDING' : 'POSTED'}</span>
                <span style={{ textAlign: 'right', fontFamily: th.mono, fontWeight: 600, color: inc ? th.pos : th.ink }}>{inc ? '+' : ''}{fmtMoney(tx.amount, th.currency)}</span>
              </div>
            );
          })}
        </div>
      </div>
    </WebShell>
  );
}

// ─────────────────────────────────────────────────────────────
// Optional · Goals
// ─────────────────────────────────────────────────────────────
function WebGoalsOverview({ th }) {
  const totalSaved = MOCK.goals.reduce((s, g) => s + g.saved, 0);
  const totalTarget = MOCK.goals.reduce((s, g) => s + g.target, 0);
  return (
    <WebShell th={th} active="goals" title="Goals" sub={`${MOCK.goals.length} active · ${Math.round((totalSaved/totalTarget)*100)}% to target`}
      actions={<div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.ink, color: th.paper, borderRadius: 18, fontSize: 13, fontWeight: 500 }}><Icon name="plus" size={14} stroke={2}/>New goal</div>}>
      <div style={{ padding: 32 }}>
        {/* Hero */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: 26, paddingBottom: 22, borderBottom: `1px solid ${th.line}` }}>
          <div>
            <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1.2, textTransform: 'uppercase' }}>Total saved · all goals</div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 14 }}>
              <div style={{ fontFamily: th.display, fontSize: 64, letterSpacing: -2.4, lineHeight: 1, marginTop: 4 }}>
                <Money value={totalSaved} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
              </div>
              <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 18, color: th.muted }}>of {fmtMoneyShort(totalTarget, th.currency)}</div>
            </div>
          </div>
          <div style={{ width: 280 }}>
            <div style={{ fontSize: 11, color: th.muted, marginBottom: 8 }}>Monthly contribution · auto-transfer</div>
            <BarChart values={[420,440,440,520,480,540]} labels={['Dec','Jan','Feb','Mar','Apr','May']} width={280} height={70} color={th.muted} highlight={th.accent} muted={th.paperAlt}/>
          </div>
        </div>

        {/* Goal grid */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16 }}>
          {MOCK.goals.map((g) => {
            const pct = (g.saved / g.target) * 100;
            return (
              <div key={g.id} style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 16, padding: 24 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 22 }}>
                  <div>
                    <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1.2, marginBottom: 4 }}>{g.eta.toUpperCase()}</div>
                    <div style={{ fontFamily: th.display, fontSize: 26, letterSpacing: -0.5, lineHeight: 1.1 }}>{g.name}</div>
                  </div>
                  <Icon name="dots" size={16} style={{ color: th.muted }}/>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 16 }}>
                  <Ring value={g.saved} max={g.target} size={84} stroke={8} color={`oklch(0.65 0.14 ${g.hue})`} track={th.paperAlt}>
                    <span style={{ fontFamily: th.mono, fontSize: 14, fontWeight: 600 }}>{Math.round(pct)}%</span>
                  </Ring>
                  <div>
                    <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.6, lineHeight: 1 }}>
                      <Money value={g.saved} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
                    </div>
                    <div style={{ fontSize: 12, color: th.muted, marginTop: 4 }}>of <Money value={g.target} currency={th.currency}/></div>
                  </div>
                </div>
                <div style={{ paddingTop: 14, borderTop: `0.5px solid ${th.line}`, display: 'flex', justifyContent: 'space-between', fontSize: 12 }}>
                  <span style={{ color: th.muted }}>Auto-save</span>
                  <span style={{ color: th.pos, fontWeight: 500 }}>+ {fmtMoneyShort(g.target / 12, th.currency)} / mo</span>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </WebShell>
  );
}

// ─────────────────────────────────────────────────────────────
// Optional · Subscriptions
// ─────────────────────────────────────────────────────────────
function WebSubscriptionsOverview({ th }) {
  const monthlyTotal = MOCK.subscriptions.reduce((s, x) => s + x.amount, 0);
  return (
    <WebShell th={th} active="subs" title="Subscriptions" sub={`${MOCK.subscriptions.length} active · ${fmtMoneyShort(monthlyTotal, th.currency)}/mo`}
      actions={<div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.ink, color: th.paper, borderRadius: 18, fontSize: 13, fontWeight: 500 }}><Icon name="plus" size={14} stroke={2}/>Add subscription</div>}>
      <div style={{ padding: 32 }}>
        {/* Hero */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 16, marginBottom: 26 }}>
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 22 }}>
            <div style={{ fontSize: 11, color: th.muted, letterSpacing: 0.6, textTransform: 'uppercase', marginBottom: 4 }}>Per month</div>
            <div style={{ fontFamily: th.display, fontSize: 36, letterSpacing: -0.8, lineHeight: 1 }}><Money value={monthlyTotal} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/></div>
          </div>
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 22 }}>
            <div style={{ fontSize: 11, color: th.muted, letterSpacing: 0.6, textTransform: 'uppercase', marginBottom: 4 }}>Per year</div>
            <div style={{ fontFamily: th.display, fontSize: 36, letterSpacing: -0.8, lineHeight: 1 }}><Money value={monthlyTotal * 12} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/></div>
          </div>
          <div style={{ background: `${th.warn}1a`, border: `1px solid ${th.warn}30`, borderRadius: 14, padding: 22 }}>
            <div style={{ fontSize: 11, color: th.warn, letterSpacing: 0.6, textTransform: 'uppercase', marginBottom: 4, fontWeight: 600 }}>Unused · suggest cancel</div>
            <div style={{ fontFamily: th.display, fontSize: 36, letterSpacing: -0.8, lineHeight: 1, color: th.warn }}><Money value={36.93} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/></div>
            <div style={{ fontSize: 11, color: th.ink2, marginTop: 6 }}>Audible · Figma Pro</div>
          </div>
        </div>

        {/* Subs list */}
        <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '50px 1fr 140px 140px 100px 100px 40px', padding: '12px 18px', fontFamily: th.mono, fontSize: 9, letterSpacing: 1.5, color: th.muted, background: th.paperAlt, borderBottom: `1px solid ${th.line}` }}>
            <span></span><span>NAME</span><span>NEXT CHARGE</span><span>CADENCE</span><span>MONTHLY</span><span>YEARLY</span><span></span>
          </div>
          {MOCK.subscriptions.map((s, i) => (
            <div key={s.id} style={{ display: 'grid', gridTemplateColumns: '50px 1fr 140px 140px 100px 100px 40px', padding: '14px 18px', alignItems: 'center', borderBottom: i < MOCK.subscriptions.length - 1 ? `0.5px solid ${th.line}` : 'none', fontSize: 13 }}>
              <div style={{ width: 36, height: 36, borderRadius: 9, background: `oklch(0.82 0.10 ${s.logoHue})`, color: th.ink, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: th.display, fontWeight: 500, fontSize: 16 }}>{s.name.charAt(0)}</div>
              <span style={{ fontWeight: 500 }}>{s.name}</span>
              <span style={{ color: th.muted, fontSize: 12 }}>{s.next}</span>
              <span style={{ color: th.muted, fontSize: 12, textTransform: 'capitalize' }}>{s.cadence}</span>
              <span style={{ fontFamily: th.mono, fontWeight: 600 }}>{fmtMoney(s.amount, th.currency)}</span>
              <span style={{ fontFamily: th.mono, color: th.muted, fontSize: 12 }}>{fmtMoneyShort(s.amount * 12, th.currency)}</span>
              <Icon name="dots" size={14} style={{ color: th.muted }}/>
            </div>
          ))}
        </div>
      </div>
    </WebShell>
  );
}

Object.assign(window, {
  WebShell, WebAccountsOverview, WebAccountDetail,
  WebBudgetsOverview, WebBudgetDetail,
  WebScheduledOverview, WebInsightsOverview,
  WebActivityOverview, WebGoalsOverview, WebSubscriptionsOverview,
  ScreenAccountDetail, ScreenBudgetDetail,
  WEB_MOBILE_W, WEB_MOBILE_H,
});
