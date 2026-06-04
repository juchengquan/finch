// Six mobile dashboard variations.
// Each returns an iOS-framed dashboard. Theme is passed in via `th`.
// Phone size: 390x844.

const PHONE_W = 390;
const PHONE_H = 844;

// Convenience: status-bar-safe top padding (clears dynamic island)
const STATUS_PAD = 56;

// Profile chip — avatar (+ tiny chev) that opens settings/profile menu.
// Used in every screen's top-right per the new header spec.
function ProfileChip({ th, size = 32 }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 4, padding: '2px 4px 2px 2px', borderRadius: 999, border: `1px solid ${th.line}`, background: th.card }}>
      <MerchantGlyph name="Alex Morgan" size={size - 6} bg={th.accent} fg="#fff"/>
      <Icon name="chev-d" size={11} style={{ color: th.muted, marginRight: 2 }}/>
    </div>
  );
}

// Top header strip — sits below the status bar, full-width, with the title or
// brand on the left and the profile chip on the right. Settings now lives
// behind the chip; dashboards keep their custom mastheads underneath.
function MobileTopBar({ th, brand = 'Finch', italic = true, trailing }) {
  return (
    <div style={{ padding: `${STATUS_PAD + 6}px 20px 12px`, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
      <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: italic ? 'italic' : 'normal', letterSpacing: -0.3, color: th.ink }}>{brand}</div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        {trailing}
        <ProfileChip th={th}/>
      </div>
    </div>
  );
}

// Bottom tabbar shared across variations.
// Default 5-item structure: Accounts · Budgets · [Add] · Scheduled · Insights.
// Settings lives behind the profile avatar in the top bar, not here.
// Users can reorder/swap these tabs from Settings → Tab layout.
// Pass `items` to override the default list. Pass `extraTabs` to swap one of
// the defaults for an optional tab (used when an optional screen is active).
function MobileTabBar({ th, active = 'insights', items, extraTabs }) {
  const defaults = [
    { id: 'accounts',  icon: 'wallet',   label: 'Accounts' },
    { id: 'budgets',   icon: 'target',   label: 'Budgets' },
    { id: 'add',       icon: 'plus',     label: '' },
    { id: 'scheduled', icon: 'calendar', label: 'Scheduled' },
    { id: 'insights',  icon: 'chart',    label: 'Insights' },
  ];
  let list = items || defaults.slice();
  if (extraTabs && !items) {
    // Replace the last slot (Insights by default) with the extra tab so a
    // user landing on an optional screen sees it pinned in their bar.
    extraTabs.forEach((e) => {
      const occupied = list.findIndex((x) => x.id === e.id);
      if (occupied >= 0) return; // already there
      // Find the rightmost non-Add slot to swap
      for (let i = list.length - 1; i >= 0; i--) {
        if (list[i].id !== 'add') { list[i] = e; break; }
      }
    });
  }
  return (
    <div style={{
      position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 30,
      paddingBottom: 30, paddingTop: 10, background: `linear-gradient(to top, ${th.paper} 60%, ${th.paper}00)`,
    }}>
      <div style={{
        margin: '0 16px', height: 56, borderRadius: 28,
        background: th.card, border: `1px solid ${th.line}`,
        display: 'flex', alignItems: 'center', justifyContent: 'space-around',
        boxShadow: '0 6px 20px rgba(0,0,0,0.04)',
      }}>
        {list.map((it) => {
          const isAdd = it.id === 'add';
          const isActive = it.id === active;
          return (
            <div key={it.id} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2 }}>
              {isAdd ? (
                <div style={{
                  width: 44, height: 44, borderRadius: 22, background: th.accent, color: '#fff',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  boxShadow: '0 4px 12px rgba(201,100,66,0.35)',
                }}>
                  <Icon name="plus" size={22} stroke={2}/>
                </div>
              ) : (
                <div style={{ color: isActive ? th.ink : th.muted, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2 }}>
                  <Icon name={it.icon} size={20}/>
                  <span style={{ fontSize: 10, fontWeight: 500, letterSpacing: 0.2 }}>{it.label}</span>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 01 · Editorial — magazine layout, big serif numbers
// ─────────────────────────────────────────────────────────────
function DashEditorial({ th }) {
  const pctOfBudget = (MOCK.monthSpent / MOCK.monthBudget) * 100;
  const remaining = MOCK.monthBudget - MOCK.monthSpent;
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ padding: `${STATUS_PAD + 10}px 24px 110px`, height: '100%', overflowY: 'auto', boxSizing: 'border-box' }}>
        {/* Masthead */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 28 }}>
          <div style={{ fontFamily: th.display, fontSize: 22, fontStyle: 'italic', letterSpacing: -0.5 }}>Finch</div>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="search" size={16}/></div>
            <ProfileChip th={th}/>
          </div>
        </div>

        {/* Hero — balance */}
        <div style={{ borderTop: `1px solid ${th.line}`, paddingTop: 18, marginBottom: 22 }}>
          <div style={{ fontSize: 10, letterSpacing: 1.2, textTransform: 'uppercase', color: th.muted, marginBottom: 8 }}>Net Worth · May 2026</div>
          <div style={{ fontFamily: th.display, fontSize: 64, lineHeight: 1, letterSpacing: -2.5, fontWeight: 400 }}>
            <Money value={MOCK.balance + 21430} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
          </div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginTop: 10 }}>
            <span style={{ color: th.pos, fontSize: 13, fontWeight: 500 }}>+ <Money value={812} currency={th.currency}/></span>
            <span style={{ color: th.muted, fontSize: 12 }}>this month</span>
          </div>
        </div>

        {/* Budget meter */}
        <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 18, padding: 20, marginBottom: 22 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: 14 }}>
            <div>
              <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 4 }}>Spent · May</div>
              <div style={{ fontFamily: th.display, fontSize: 34, letterSpacing: -1 }}><Money value={MOCK.monthSpent} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/></div>
            </div>
            <div style={{ textAlign: 'right' }}>
              <div style={{ fontSize: 11, color: th.muted, marginBottom: 4 }}>of <Money value={MOCK.monthBudget} currency={th.currency}/></div>
              <div style={{ fontSize: 12, color: th.pos, fontWeight: 500 }}>{Math.round(pctOfBudget)}% used</div>
            </div>
          </div>
          <div style={{ height: 4, background: th.paperAlt, borderRadius: 2, overflow: 'hidden' }}>
            <div style={{ width: `${pctOfBudget}%`, height: '100%', background: th.accent }}/>
          </div>
          <div style={{ marginTop: 10, fontSize: 12, color: th.ink2 }}>
            <Money value={remaining} currency={th.currency}/> left for 7 days · <Money value={remaining/7} currency={th.currency}/>/day
          </div>
        </div>

        {/* Categories — list with category names as editorial labels */}
        <div style={{ marginBottom: 10, display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <div style={{ fontFamily: th.display, fontSize: 22, fontStyle: 'italic' }}>Categories</div>
          <span style={{ fontSize: 12, color: th.muted }}>See all →</span>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
          {MOCK.categories.slice(0, 5).map((cat, i) => {
            const pct = (cat.spent / cat.budget) * 100;
            const over = pct > 100;
            return (
              <div key={cat.id} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 0', borderTop: `1px solid ${th.line}` }}>
                <div style={{ width: 36, height: 36, borderRadius: 18, background: `oklch(0.92 0.04 ${cat.hue})`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}>
                  <Icon name={cat.icon} size={18}/>
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                    <div style={{ fontSize: 15, fontWeight: 500 }}>{cat.name}</div>
                    <div style={{ fontSize: 14, fontVariantNumeric: 'tabular-nums', color: over ? th.neg : th.ink }}><Money value={cat.spent} currency={th.currency}/></div>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 4 }}>
                    <div style={{ flex: 1, height: 2, background: th.paperAlt, marginRight: 12, overflow: 'hidden' }}>
                      <div style={{ width: `${Math.min(pct, 100)}%`, height: '100%', background: over ? th.neg : th.accent }}/>
                    </div>
                    <div style={{ fontSize: 11, color: th.muted, fontVariantNumeric: 'tabular-nums' }}>of <Money value={cat.budget} currency={th.currency}/></div>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>
      <MobileTabBar th={th} active="home"/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 02 · Minimal Mono — tight typographic list, mono numbers
// ─────────────────────────────────────────────────────────────
function DashMono({ th }) {
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ padding: `${STATUS_PAD + 12}px 20px 110px`, height: '100%', overflowY: 'auto', boxSizing: 'border-box' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontFamily: th.mono, fontSize: 11, color: th.muted, letterSpacing: 0.5, marginBottom: 16 }}>
          <span>SAT 24 MAY · WEEK 21</span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}><span style={{ width: 6, height: 6, borderRadius: 3, background: th.pos }}/>SYNCED</span>
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 22 }}>
          <div style={{ fontFamily: th.display, fontSize: 20, fontStyle: 'italic', color: th.ink }}>Finch</div>
          <ProfileChip th={th}/>
        </div>

        {/* Balance line */}
        <div style={{ marginBottom: 8, fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1 }}>NET BALANCE</div>
        <div style={{ fontSize: 44, fontWeight: 300, letterSpacing: -2, fontVariantNumeric: 'tabular-nums', marginBottom: 4 }}>
          <Money value={MOCK.balance} currency={th.currency}/>
        </div>
        <div style={{ fontFamily: th.mono, fontSize: 12, color: th.pos, marginBottom: 26 }}>+2.18% ▲ from prev week</div>

        {/* Sparkline */}
        <div style={{ marginBottom: 28 }}>
          <Sparkline values={MOCK.daily.slice(-14)} width={350} height={56} color={th.accent} stroke={1.25}/>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: th.mono, fontSize: 10, color: th.muted, marginTop: 4, letterSpacing: 0.5 }}>
            <span>14 DAYS</span><span>TODAY</span>
          </div>
        </div>

        {/* Three columns */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 1, background: th.line, border: `1px solid ${th.line}`, marginBottom: 28 }}>
          {[
            { label: 'IN',   v: MOCK.monthIncome,  color: th.pos },
            { label: 'OUT',  v: MOCK.monthSpent,   color: th.ink },
            { label: 'NET',  v: MOCK.monthIncome - MOCK.monthSpent, color: th.accent },
          ].map((s) => (
            <div key={s.label} style={{ background: th.paper, padding: '14px 12px' }}>
              <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1, marginBottom: 4 }}>{s.label}</div>
              <div style={{ fontSize: 16, fontWeight: 500, color: s.color, fontVariantNumeric: 'tabular-nums' }}><Money value={s.v} currency={th.currency}/></div>
            </div>
          ))}
        </div>

        {/* Transaction list — typographic */}
        <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1, marginBottom: 10, display: 'flex', justifyContent: 'space-between' }}>
          <span>RECENT</span><span>{MOCK.transactions.length} ITEMS</span>
        </div>
        {MOCK.transactions.slice(0, 8).map((tx, i) => {
          const cat = catById(tx.category);
          const inc = tx.amount > 0;
          return (
            <div key={tx.id} style={{ display: 'flex', alignItems: 'center', padding: '10px 0', borderTop: i ? `1px solid ${th.line}` : 'none' }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 14, fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{tx.merchant}</div>
                <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.5, marginTop: 2 }}>
                  {tx.date.slice(5).replace('-','/')} · {cat.name.toUpperCase()}{tx.pending ? ' · PENDING' : ''}
                </div>
              </div>
              <div style={{ fontSize: 14, fontWeight: 500, color: inc ? th.pos : th.ink, fontVariantNumeric: 'tabular-nums' }}>
                {inc ? '+' : ''}<Money value={tx.amount} currency={th.currency}/>
              </div>
            </div>
          );
        })}
      </div>
      <MobileTabBar th={th} active="home"/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 03 · Donut Hero — large donut + arc legend
// ─────────────────────────────────────────────────────────────
function DashDonut({ th }) {
  const slices = MOCK.categories.map((c) => ({ value: c.spent, color: `oklch(0.65 0.13 ${c.hue})`, label: c.name }));
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ padding: `${STATUS_PAD + 12}px 20px 110px`, height: '100%', overflowY: 'auto', boxSizing: 'border-box' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 }}>
          <div>
            <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 2 }}>Spent · This month</div>
            <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.5 }}>Where it went</div>
          </div>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="filter" size={16}/></div>
            <ProfileChip th={th}/>
          </div>
        </div>

        {/* Donut */}
        <div style={{ display: 'flex', justifyContent: 'center', position: 'relative', marginBottom: 24 }}>
          <Donut slices={slices} size={240} stroke={28} gap={3}/>
          <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
            <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1, textTransform: 'uppercase' }}>Total</div>
            <div style={{ fontFamily: th.display, fontSize: 36, letterSpacing: -1, marginTop: 2 }}><Money value={MOCK.monthSpent} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/></div>
            <div style={{ fontSize: 12, color: th.pos, marginTop: 2 }}>↓ 8.4% vs Apr</div>
          </div>
        </div>

        {/* Legend grid */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, marginBottom: 24 }}>
          {MOCK.categories.slice(0, 6).map((c) => {
            const pct = Math.round((c.spent / MOCK.monthSpent) * 100);
            return (
              <div key={c.id} style={{ display: 'flex', alignItems: 'center', gap: 10, background: th.card, border: `1px solid ${th.line}`, borderRadius: 12, padding: '10px 12px' }}>
                <span style={{ width: 12, height: 12, borderRadius: 6, background: `oklch(0.65 0.13 ${c.hue})`, flexShrink: 0 }}/>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 12, color: th.muted, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{c.name}</div>
                  <div style={{ fontSize: 14, fontWeight: 500, fontVariantNumeric: 'tabular-nums' }}><Money value={c.spent} currency={th.currency}/></div>
                </div>
                <div style={{ fontFamily: th.mono, fontSize: 11, color: th.muted }}>{pct}%</div>
              </div>
            );
          })}
        </div>

        {/* Insight nudge */}
        <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 14, display: 'flex', gap: 12, alignItems: 'flex-start' }}>
          <div style={{ width: 32, height: 32, borderRadius: 16, background: th.accent, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><Icon name="sparkle" size={16}/></div>
          <div style={{ fontSize: 13, color: th.ink2, lineHeight: 1.45 }}>
            You spent <b style={{ color: th.ink }}>4× more on Shopping</b> this week than last. <span style={{ color: th.muted }}>See why →</span>
          </div>
        </div>
      </div>
      <MobileTabBar th={th} active="home"/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 04 · Calendar Heatmap — month grid of daily spend
// ─────────────────────────────────────────────────────────────
function DashCalendar({ th }) {
  // Build 31-day list padded for May 2026 (May 1 was a Friday)
  const days = [];
  for (let i = 0; i < 4; i++) days.push(null); // pad to Friday
  for (let i = 0; i < 30; i++) days.push({ day: i + 1, v: MOCK.daily[i] || 0 });
  // Pad to multiple of 7
  while (days.length % 7) days.push(null);
  const max = Math.max(...MOCK.daily);

  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ padding: `${STATUS_PAD + 12}px 20px 110px`, height: '100%', overflowY: 'auto', boxSizing: 'border-box' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 18 }}>
          <div>
            <div style={{ fontFamily: th.display, fontSize: 36, letterSpacing: -1, lineHeight: 1 }}>May</div>
            <div style={{ fontSize: 12, color: th.muted, marginTop: 4 }}>{MOCK.user.name.split(' ')[0]}'s spend journal</div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <div style={{ width: 32, height: 32, borderRadius: 16, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="chev-l" size={14}/></div>
            <div style={{ width: 32, height: 32, borderRadius: 16, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="chev" size={14}/></div>
            <ProfileChip th={th}/>
          </div>
        </div>

        {/* Totals strip */}
        <div style={{ display: 'flex', gap: 12, marginBottom: 18 }}>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 10, color: th.muted, letterSpacing: 1, textTransform: 'uppercase' }}>Total</div>
            <div style={{ fontSize: 22, fontWeight: 500, marginTop: 2 }}><Money value={MOCK.monthSpent} currency={th.currency}/></div>
          </div>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 10, color: th.muted, letterSpacing: 1, textTransform: 'uppercase' }}>Avg/day</div>
            <div style={{ fontSize: 22, fontWeight: 500, marginTop: 2 }}><Money value={MOCK.monthSpent / 24} currency={th.currency}/></div>
          </div>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 10, color: th.muted, letterSpacing: 1, textTransform: 'uppercase' }}>Spendy day</div>
            <div style={{ fontSize: 22, fontWeight: 500, marginTop: 2 }}>8</div>
          </div>
        </div>

        {/* Calendar grid */}
        <div style={{ border: `1px solid ${th.line}`, borderRadius: 14, padding: 14, background: th.card, marginBottom: 20 }}>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7,1fr)', gap: 6, marginBottom: 6 }}>
            {['M','T','W','T','F','S','S'].map((d, i) => (
              <div key={i} style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, textAlign: 'center', letterSpacing: 1 }}>{d}</div>
            ))}
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7,1fr)', gap: 6 }}>
            {days.map((d, i) => {
              if (!d) return <div key={i} style={{ aspectRatio: '1', }}/>;
              const opacity = d.v === 0 ? 0 : 0.18 + 0.82 * (d.v / max);
              const isToday = d.day === 24;
              return (
                <div key={i} style={{
                  aspectRatio: '1', position: 'relative',
                  background: th.paperAlt, borderRadius: 6, overflow: 'hidden',
                  outline: isToday ? `1.5px solid ${th.ink}` : 'none', outlineOffset: -1,
                }}>
                  {d.v > 0 && <div style={{ position: 'absolute', inset: 0, background: th.accent, opacity }}/>}
                  <div style={{ position: 'absolute', top: 4, left: 5, fontSize: 11, fontWeight: 500, color: d.v > max * 0.5 ? '#fff' : th.ink }}>{d.day}</div>
                  {d.v > max * 0.3 && <div style={{ position: 'absolute', bottom: 3, right: 5, fontFamily: th.mono, fontSize: 8, color: '#fff', fontWeight: 500 }}>{fmtMoneyShort(d.v, th.currency)}</div>}
                </div>
              );
            })}
          </div>
        </div>

        {/* Legend */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, fontSize: 10, color: th.muted, letterSpacing: 0.5, marginBottom: 22 }}>
          <span>LESS</span>
          {[0.15, 0.3, 0.5, 0.7, 0.95].map((o) => (
            <div key={o} style={{ width: 16, height: 8, borderRadius: 2, background: th.accent, opacity: o }}/>
          ))}
          <span>MORE</span>
        </div>

        {/* Today's transactions */}
        <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 10 }}>Today · 2 transactions</div>
        {MOCK.transactions.slice(0, 2).map((tx, i) => (
          <div key={tx.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 0', borderTop: i ? `1px solid ${th.line}` : 'none' }}>
            <MerchantGlyph name={tx.merchant} size={32} hue={catById(tx.category).hue}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 14, fontWeight: 500 }}>{tx.merchant}</div>
              <div style={{ fontSize: 11, color: th.muted }}>{tx.time} · {catById(tx.category).name}</div>
            </div>
            <Money value={tx.amount} currency={th.currency} style={{ fontSize: 14, fontWeight: 500 }}/>
          </div>
        ))}
      </div>
      <MobileTabBar th={th} active="home"/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 05 · Stacked Bars — bars dominant, all categories ranked
// ─────────────────────────────────────────────────────────────
function DashStacked({ th }) {
  const cats = [...MOCK.categories].sort((a, b) => b.spent - a.spent);
  const max = Math.max(...cats.map((c) => c.budget));
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ padding: `${STATUS_PAD + 12}px 20px 110px`, height: '100%', overflowY: 'auto', boxSizing: 'border-box' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 22 }}>
          <div style={{ fontFamily: th.display, fontSize: 20, fontStyle: 'italic', color: th.ink }}>Finch</div>
          <ProfileChip th={th}/>
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: 22 }}>
          <div>
            <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 4 }}>May Spending</div>
            <div style={{ fontSize: 40, fontWeight: 600, letterSpacing: -1.5, lineHeight: 1 }}><Money value={MOCK.monthSpent} currency={th.currency}/></div>
          </div>
          <div style={{ textAlign: 'right' }}>
            <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1, textTransform: 'uppercase' }}>Budget</div>
            <div style={{ fontSize: 14, fontWeight: 500, marginTop: 4 }}><Money value={MOCK.monthBudget} currency={th.currency}/></div>
          </div>
        </div>

        {/* One stacked overall bar */}
        <div style={{ marginBottom: 8 }}>
          <StackedBar
            slices={cats.map((c) => ({ value: c.spent, color: `oklch(0.65 0.13 ${c.hue})` }))}
            width={350} height={12} radius={6} gap={2}
          />
          <div style={{ display: 'flex', gap: 10, marginTop: 10, flexWrap: 'wrap' }}>
            {cats.slice(0, 4).map((c) => (
              <div key={c.id} style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11, color: th.ink2 }}>
                <span style={{ width: 8, height: 8, borderRadius: 4, background: `oklch(0.65 0.13 ${c.hue})` }}/>
                {c.name}
              </div>
            ))}
          </div>
        </div>

        <div style={{ height: 1, background: th.line, margin: '24px 0' }}/>

        {/* Bars per category */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 12 }}>
          <div style={{ fontSize: 14, fontWeight: 600 }}>Categories</div>
          <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1 }}>SPENT / BUDGET</div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          {cats.map((c) => {
            const spentPct = (c.spent / max) * 100;
            const budgetPct = (c.budget / max) * 100;
            const over = c.spent > c.budget;
            return (
              <div key={c.id}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 5 }}>
                  <div style={{ fontSize: 13, fontWeight: 500 }}>{c.name}</div>
                  <div style={{ fontFamily: th.mono, fontSize: 11, color: over ? th.neg : th.ink }}>
                    {fmtMoneyShort(c.spent, th.currency)} / {fmtMoneyShort(c.budget, th.currency)}
                  </div>
                </div>
                <div style={{ position: 'relative', height: 8, background: th.paperAlt, borderRadius: 4, overflow: 'hidden' }}>
                  <div style={{ position: 'absolute', left: 0, top: 0, height: '100%', width: `${spentPct}%`, background: over ? th.neg : `oklch(0.65 0.13 ${c.hue})`, borderRadius: 4 }}/>
                  <div style={{ position: 'absolute', left: `${budgetPct}%`, top: -2, bottom: -2, width: 2, background: th.ink2, opacity: 0.5 }}/>
                </div>
              </div>
            );
          })}
        </div>
      </div>
      <MobileTabBar th={th} active="home"/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 06 · Stream — flowing area + cashflow narrative
// ─────────────────────────────────────────────────────────────
function DashStream({ th }) {
  const incSeries = MOCK.cashflow.map((c) => c.inc);
  const expSeries = MOCK.cashflow.map((c) => c.exp);
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ padding: `${STATUS_PAD + 12}px 20px 110px`, height: '100%', overflowY: 'auto', boxSizing: 'border-box' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 18 }}>
          <div style={{ fontFamily: th.display, fontSize: 22, fontStyle: 'italic', letterSpacing: -0.3 }}>Good morning, Alex</div>
          <ProfileChip th={th}/>
        </div>

        {/* Cashflow hero */}
        <div style={{ background: th.ink, color: th.paper, borderRadius: 22, padding: 22, marginBottom: 18, position: 'relative', overflow: 'hidden' }}>
          <div style={{ fontSize: 11, opacity: 0.55, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 4 }}>Cashflow · last 5 mo</div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 18 }}>
            <div>
              <div style={{ fontFamily: th.display, fontSize: 38, lineHeight: 1, letterSpacing: -1 }}><Money value={3362} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/></div>
              <div style={{ fontSize: 12, opacity: 0.7, marginTop: 6 }}>saved this month</div>
            </div>
            <div style={{ background: th.accent, color: '#fff', borderRadius: 12, padding: '4px 10px', fontSize: 11, fontWeight: 600 }}>↑ 22%</div>
          </div>
          <div style={{ height: 90, position: 'relative' }}>
            <AreaChart series={[incSeries, expSeries]} width={344} height={90} colors={[th.accent2, '#f5f1ea']} smooth/>
            <div style={{ position: 'absolute', bottom: -22, left: 0, right: 0, display: 'flex', justifyContent: 'space-between', fontFamily: th.mono, fontSize: 9, opacity: 0.55, letterSpacing: 1 }}>
              {MOCK.cashflow.map((c) => <span key={c.m}>{c.m.toUpperCase()}</span>)}
            </div>
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 18 }}>
          {/* Income card */}
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 16, padding: 14 }}>
            <div style={{ fontSize: 10, color: th.muted, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 4 }}>Income · May</div>
            <div style={{ fontSize: 18, fontWeight: 600 }}><Money value={MOCK.monthIncome} currency={th.currency}/></div>
            <div style={{ marginTop: 8 }}>
              <Sparkline values={incSeries} width={140} height={28} color={th.pos} stroke={1.5}/>
            </div>
          </div>
          {/* Expense card */}
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 16, padding: 14 }}>
            <div style={{ fontSize: 10, color: th.muted, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 4 }}>Spend · May</div>
            <div style={{ fontSize: 18, fontWeight: 600 }}><Money value={MOCK.monthSpent} currency={th.currency}/></div>
            <div style={{ marginTop: 8 }}>
              <Sparkline values={expSeries} width={140} height={28} color={th.accent} stroke={1.5}/>
            </div>
          </div>
        </div>

        {/* Upcoming bills strip */}
        <div style={{ marginBottom: 12, display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic' }}>Upcoming</div>
          <span style={{ fontSize: 11, color: th.muted }}>4 bills · {fmtMoneyShort(2845, th.currency)}</span>
        </div>
        <div style={{ display: 'flex', gap: 10, overflowX: 'auto', marginLeft: -20, paddingLeft: 20, marginRight: -20, paddingRight: 20 }}>
          {MOCK.bills.map((b) => (
            <div key={b.id} style={{ flexShrink: 0, width: 160, background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 14 }}>
              <div style={{ fontSize: 10, color: th.muted, letterSpacing: 0.8, textTransform: 'uppercase', marginBottom: 4 }}>{b.dueDate}</div>
              <div style={{ fontSize: 13, fontWeight: 500, lineHeight: 1.25, marginBottom: 10, height: 32, overflow: 'hidden' }}>{b.name}</div>
              <div style={{ fontSize: 16, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}><Money value={b.amount} currency={th.currency}/></div>
            </div>
          ))}
        </div>
      </div>
      <MobileTabBar th={th} active="home"/>
    </div>
  );
}

Object.assign(window, { DashEditorial, DashMono, DashDonut, DashCalendar, DashStacked, DashStream, MobileTabBar, MobileTopBar, ProfileChip, PHONE_W, PHONE_H, STATUS_PAD });
