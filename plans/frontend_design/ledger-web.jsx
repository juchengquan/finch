// Desktop screens for the ledger-schema concepts. Each wraps WebShell so
// the same sidebar chrome carries through.

// ─────────────────────────────────────────────────────────────
// 1 · Ledger admin — list, switch, settings
// ─────────────────────────────────────────────────────────────
function WebLedgerAdmin({ th }) {
  return (
    <WebShell th={th} active="settings" title="Ledgers" sub={`${LEDGER.ledgers.length} books · isolated · data never crosses`}
      actions={<div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.ink, color: th.paper, borderRadius: 18, fontSize: 13, fontWeight: 500 }}><Icon name="plus" size={14} stroke={2}/>New ledger</div>}>
      <div style={{ padding: 32 }}>
        {/* Intro */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 32, paddingBottom: 22, marginBottom: 22, borderBottom: `1px solid ${th.line}` }}>
          <div style={{ maxWidth: 540 }}>
            <SchemaChip th={th} label="table: ledgers"/>
            <div style={{ fontFamily: th.display, fontSize: 38, letterSpacing: -1, lineHeight: 1.1, marginTop: 10 }}>
              <span style={{ fontStyle: 'italic', color: th.muted }}>A ledger is</span> a complete set of books.
            </div>
            <div style={{ fontSize: 14, color: th.ink2, marginTop: 10, lineHeight: 1.5 }}>
              Every account, transaction and budget belongs to exactly one ledger. Switching ledgers is like opening a different filing cabinet — none of the data crosses.
            </div>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, auto)', gap: 24, fontFamily: th.mono, fontSize: 11 }}>
            {[['LEDGERS', LEDGER.ledgers.length],['ACTIVE', '1'],['BASE CCYS','3']].map(([k,v]) => (
              <div key={k}>
                <div style={{ color: th.muted, letterSpacing: 1 }}>{k}</div>
                <div style={{ fontFamily: th.display, fontSize: 36, color: th.ink, letterSpacing: -0.6, marginTop: 2 }}>{v}</div>
              </div>
            ))}
          </div>
        </div>

        {/* Table */}
        <div style={{ border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden', background: th.card }}>
          {/* head */}
          <div style={{ display: 'grid', gridTemplateColumns: '36px 1.6fr 1fr 90px 100px 100px 80px', alignItems: 'center', gap: 16, padding: '14px 18px', borderBottom: `1px solid ${th.line}`, fontFamily: th.mono, fontSize: 10, letterSpacing: 1, color: th.muted }}>
            <div/><div>NAME</div><div>TAGLINE</div><div>BASE</div><div>ACCOUNTS</div><div>TXNS</div><div style={{ textAlign: 'right' }}>STATE</div>
          </div>
          {LEDGER.ledgers.map((l, i) => {
            const isActive = l.id === LEDGER.active;
            return (
              <div key={l.id} style={{ display: 'grid', gridTemplateColumns: '36px 1.6fr 1fr 90px 100px 100px 80px', alignItems: 'center', gap: 16, padding: '16px 18px', borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
                <div style={{ width: 36, height: 36, borderRadius: 8, background: l.color, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: th.display, fontStyle: 'italic', fontSize: 20 }}>{l.name.charAt(0)}</div>
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <div style={{ fontSize: 14, fontWeight: 500 }}>{l.name}</div>
                    {l.isDefault === 1 && <span style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 0.6 }}>DEFAULT</span>}
                  </div>
                  <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, marginTop: 2, letterSpacing: 0.3 }}>{l.id}</div>
                </div>
                <div style={{ fontSize: 12, color: th.ink2 }}>{l.tagline}</div>
                <div style={{ fontFamily: th.mono, fontSize: 12 }}>{l.base}</div>
                <div style={{ fontFamily: th.body, fontSize: 13 }}>{l.accounts}</div>
                <div style={{ fontFamily: th.body, fontSize: 13 }}>{l.txns.toLocaleString()}</div>
                <div style={{ textAlign: 'right' }}>
                  {isActive ? (
                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontFamily: th.mono, fontSize: 10, color: th.pos, letterSpacing: 0.6, padding: '3px 8px', background: `${th.pos}18`, borderRadius: 4 }}>● ACTIVE</span>
                  ) : (
                    <span style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.6 }}>switch →</span>
                  )}
                </div>
              </div>
            );
          })}
        </div>

        {/* Footnote */}
        <div style={{ marginTop: 18, padding: 16, background: th.paperAlt, borderRadius: 10, display: 'flex', gap: 12, alignItems: 'flex-start' }}>
          <Icon name="sparkle" size={16} style={{ color: th.warn, marginTop: 2, flexShrink: 0 }}/>
          <div style={{ fontSize: 12, color: th.ink2, lineHeight: 1.5 }}>
            Cross-ledger transfers (e.g. <i>Personal → Side studio</i>) are tracked through <span style={{ fontFamily: th.mono }}>transfer_groups</span>. Both sides keep the same <span style={{ fontFamily: th.mono }}>amount_base</span> so totals in each ledger reconcile without double-counting.
          </div>
        </div>
      </div>
    </WebShell>
  );
}

// ─────────────────────────────────────────────────────────────
// 2 · Pending review queue (desktop)
// ─────────────────────────────────────────────────────────────
function WebPendingReview({ th }) {
  return (
    <WebShell th={th} active="activity" title="Pending review" sub={`${LEDGER.pending.length} items · excluded from reports until confirmed`}
      actions={<div style={{ display: 'flex', gap: 8 }}>
        <div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, border: `1px solid ${th.line}`, borderRadius: 18, fontSize: 13 }}>Cancel all</div>
        <div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.ink, color: th.paper, borderRadius: 18, fontSize: 13, fontWeight: 500 }}><Icon name="check" size={14} stroke={2}/>Confirm all</div>
      </div>}>
      <div style={{ padding: 32, display: 'grid', gridTemplateColumns: '1fr 320px', gap: 32 }}>
        {/* Main table */}
        <div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 16, paddingBottom: 18, marginBottom: 18, borderBottom: `1px solid ${th.line}` }}>
            <SchemaChip th={th} label="status = pending"/>
            <div style={{ fontFamily: th.display, fontSize: 32, letterSpacing: -0.8, fontStyle: 'italic' }}>4 items awaiting you</div>
          </div>

          <div style={{ border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden', background: th.card }}>
            <div style={{ display: 'grid', gridTemplateColumns: '36px 1.6fr 0.9fr 0.9fr 1fr 120px', alignItems: 'center', gap: 14, padding: '12px 18px', borderBottom: `1px solid ${th.line}`, fontFamily: th.mono, fontSize: 10, letterSpacing: 1, color: th.muted }}>
              <div/><div>MERCHANT</div><div>ACCOUNT</div><div>DATE</div><div>WHY PENDING</div><div style={{ textAlign: 'right' }}>AMOUNT</div>
            </div>
            {LEDGER.pending.map((p, i) => {
              const inc = p.amount > 0;
              const isFx = p.currency !== 'SGD';
              return (
                <div key={p.id}>
                  <div style={{ display: 'grid', gridTemplateColumns: '36px 1.6fr 0.9fr 0.9fr 1fr 120px', alignItems: 'center', gap: 14, padding: '14px 18px', borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
                    <MerchantGlyph name={p.merchant} size={32} hue={(i*60) % 360}/>
                    <div>
                      <div style={{ fontSize: 14, fontWeight: 500 }}>{p.merchant}</div>
                      <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, marginTop: 2 }}>{p.source}</div>
                    </div>
                    <div style={{ fontSize: 13 }}>{p.account}</div>
                    <div style={{ fontFamily: th.mono, fontSize: 12, color: th.ink2 }}>{p.date.replace(/-/g,'/')}</div>
                    <div style={{ fontSize: 12, color: th.ink2, lineHeight: 1.35 }}>{p.reason}</div>
                    <div style={{ textAlign: 'right' }}>
                      <div style={{ fontFamily: th.body, fontSize: 15, fontWeight: 500, color: inc ? th.pos : th.ink }}>
                        {inc ? '+' : ''}{p.currency === 'JPY' ? '¥' : 'S$'}{Math.abs(p.amount).toLocaleString()}
                      </div>
                      {isFx && <div style={{ fontFamily: th.mono, fontSize: 10, color: th.warn, marginTop: 2 }}>{p.currency} · FX</div>}
                    </div>
                  </div>
                  {/* Action row */}
                  <div style={{ padding: '0 18px 14px 70px', display: 'flex', gap: 6 }}>
                    <div style={{ height: 26, padding: '0 12px', background: th.ink, color: th.paper, borderRadius: 13, display: 'flex', alignItems: 'center', gap: 5, fontSize: 11, fontWeight: 500 }}>
                      <Icon name="check" size={11} stroke={2}/>Confirm
                    </div>
                    <div style={{ height: 26, padding: '0 10px', border: `1px solid ${th.line}`, borderRadius: 13, display: 'flex', alignItems: 'center', fontSize: 11, color: th.ink }}>Edit</div>
                    <div style={{ height: 26, padding: '0 10px', border: `1px solid ${th.line}`, borderRadius: 13, display: 'flex', alignItems: 'center', fontSize: 11, color: th.muted }}>Cancel</div>
                    {p.source !== 'rt-salary' && (
                      <div style={{ height: 26, padding: '0 10px', border: `1px solid ${th.line}`, borderRadius: 13, display: 'flex', alignItems: 'center', fontSize: 11, color: th.muted }}>+ standardise merchant</div>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Side panel — what pending means */}
        <div>
          <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.2, color: th.muted, marginBottom: 10 }}>HOW PENDING WORKS</div>
          <div style={{ fontFamily: th.display, fontSize: 22, letterSpacing: -0.4, lineHeight: 1.2, marginBottom: 14 }}>
            <i>Pending</i> items don't reach reports until you confirm them.
          </div>
          <div style={{ fontSize: 13, color: th.ink2, lineHeight: 1.55, marginBottom: 18 }}>
            Two sources create pending items: recurring templates with <span style={{ fontFamily: th.mono }}>auto_post = 0</span>, and CSV imports that hit an unverified merchant or missing exchange rate.
          </div>

          <div style={{ padding: 14, background: th.card, border: `1px solid ${th.line}`, borderRadius: 10, marginBottom: 8 }}>
            <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 0.6, marginBottom: 6 }}>STATE MACHINE</div>
            {[
              ['pending',   '→ confirmed', '✓ counted in reports'],
              ['pending',   '→ cancelled', '× ignored forever'],
              ['confirmed', '→ cancelled', '↺ summary reversed'],
            ].map(([a, b, c]) => (
              <div key={a+b} style={{ display: 'grid', gridTemplateColumns: '70px 90px 1fr', gap: 8, fontFamily: th.mono, fontSize: 11, padding: '5px 0' }}>
                <span style={{ color: th.muted }}>{a}</span>
                <span style={{ color: th.ink }}>{b}</span>
                <span style={{ color: th.ink2 }}>{c}</span>
              </div>
            ))}
          </div>

          <div style={{ padding: 14, background: th.paperAlt, borderRadius: 10, fontSize: 12, color: th.ink2, lineHeight: 1.5 }}>
            Triggers in the DB keep <span style={{ fontFamily: th.mono }}>ledger_summaries</span> in sync — confirm or cancel here, and your monthly totals re-balance instantly.
          </div>
        </div>
      </div>
    </WebShell>
  );
}

// ─────────────────────────────────────────────────────────────
// 3 · Counterparties (merchant directory)
// ─────────────────────────────────────────────────────────────
function WebCounterparties({ th }) {
  return (
    <WebShell th={th} active="activity" title="Merchants" sub="Canonical names and their aliases — used to unify imported descriptions"
      actions={<div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.ink, color: th.paper, borderRadius: 18, fontSize: 13, fontWeight: 500 }}><Icon name="plus" size={14} stroke={2}/>New merchant</div>}>
      <div style={{ padding: '24px 32px 32px' }}>
        {/* Top stats + chip */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', paddingBottom: 22, marginBottom: 22, borderBottom: `1px solid ${th.line}` }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 28 }}>
            <div>
              <SchemaChip th={th} label="table: counterparties"/>
              <div style={{ fontFamily: th.display, fontSize: 38, letterSpacing: -1, lineHeight: 1, marginTop: 10 }}>{LEDGER.counterparties.length}</div>
              <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1, marginTop: 4 }}>STANDARDISED</div>
            </div>
            <div style={{ width: 1, height: 56, background: th.line, alignSelf: 'flex-end' }}/>
            <div>
              <div style={{ fontFamily: th.display, fontSize: 38, letterSpacing: -1, lineHeight: 1, color: th.warn }}>{LEDGER.counterparties.filter(c=>!c.verified).length}</div>
              <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1, marginTop: 4 }}>UNVERIFIED</div>
            </div>
            <div style={{ width: 1, height: 56, background: th.line, alignSelf: 'flex-end' }}/>
            <div>
              <div style={{ fontFamily: th.display, fontSize: 38, letterSpacing: -1, lineHeight: 1 }}>{LEDGER.counterparties.reduce((s,c)=>s+c.aliases.length,0)}</div>
              <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 1, marginTop: 4 }}>ALIASES CACHED</div>
            </div>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 8, background: th.paperAlt, borderRadius: 18, color: th.muted, fontSize: 13, minWidth: 280 }}>
              <Icon name="search" size={14}/>Search merchants & aliases…
            </div>
          </div>
        </div>

        {/* Match logic explainer */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, marginBottom: 22 }}>
          {[
            ['1', 'Exact match',     'standardized_name = description'],
            ['2', 'Case-insensitive', 'lower(name) match'],
            ['3', 'Fuzzy alias',     'against aliases JSON array'],
            ['4', 'No match',        'new row, is_verified = 0'],
          ].map(([n, t, sub]) => (
            <div key={n} style={{ padding: 14, background: th.card, border: `1px solid ${th.line}`, borderRadius: 10 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
                <span style={{ width: 18, height: 18, borderRadius: 9, background: th.ink, color: th.paper, fontFamily: th.mono, fontSize: 10, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{n}</span>
                <span style={{ fontSize: 13, fontWeight: 500 }}>{t}</span>
              </div>
              <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.2 }}>{sub}</div>
            </div>
          ))}
        </div>

        {/* Table */}
        <div style={{ border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden', background: th.card }}>
          <div style={{ display: 'grid', gridTemplateColumns: '36px 1.2fr 2fr 1fr 80px 80px', alignItems: 'center', gap: 14, padding: '12px 18px', borderBottom: `1px solid ${th.line}`, fontFamily: th.mono, fontSize: 10, letterSpacing: 1, color: th.muted }}>
            <div/><div>NAME</div><div>ALIASES</div><div>CATEGORY</div><div style={{ textAlign: 'right' }}>USES</div><div style={{ textAlign: 'right' }}>VERIFIED</div>
          </div>
          {LEDGER.counterparties.map((c, i) => (
            <div key={c.id} style={{ display: 'grid', gridTemplateColumns: '36px 1.2fr 2fr 1fr 80px 80px', alignItems: 'center', gap: 14, padding: '14px 18px', borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
              <MerchantGlyph name={c.name} size={32} hue={c.hue}/>
              <div style={{ fontSize: 14, fontWeight: 500 }}>{c.name}</div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4 }}>
                {c.aliases.map((a) => (
                  <span key={a} style={{ fontFamily: th.mono, fontSize: 10, padding: '2px 7px', background: th.paperAlt, color: th.ink2, borderRadius: 4 }}>{a}</span>
                ))}
              </div>
              <div style={{ fontSize: 12, color: th.ink2 }}>{c.category}</div>
              <div style={{ textAlign: 'right', fontFamily: th.mono, fontSize: 12 }}>{c.txCount}</div>
              <div style={{ textAlign: 'right' }}>
                {c.verified ? (
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontFamily: th.mono, fontSize: 10, color: th.pos, letterSpacing: 0.6 }}><Icon name="check" size={11} stroke={2.4}/>YES</span>
                ) : (
                  <span style={{ fontFamily: th.mono, fontSize: 10, color: th.warn, letterSpacing: 0.6, padding: '2px 6px', border: `1px solid ${th.warn}66`, borderRadius: 4 }}>REVIEW</span>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </WebShell>
  );
}

// ─────────────────────────────────────────────────────────────
// 4 · Recurring templates list (desktop)
// ─────────────────────────────────────────────────────────────
function WebRecurringTemplates({ th }) {
  const total = LEDGER.recurringTemplates.reduce((s, t) => {
    if (t.type === 'income') return s + (t.amount || 0);
    if (t.type === 'expense') return s - (t.amount || 0);
    return s;
  }, 0);
  return (
    <WebShell th={th} active="sched" title="Recurring" sub={`${LEDGER.recurringTemplates.length} templates · expected net S$${total.toFixed(0)} / mo`}
      actions={<div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.ink, color: th.paper, borderRadius: 18, fontSize: 13, fontWeight: 500 }}><Icon name="plus" size={14} stroke={2}/>New template</div>}>
      <div style={{ padding: 32, display: 'grid', gridTemplateColumns: '1.5fr 1fr', gap: 28 }}>
        {/* Left — list */}
        <div>
          <SchemaChip th={th} label="recurring_templates"/>
          <div style={{ fontFamily: th.display, fontSize: 30, letterSpacing: -0.6, marginTop: 10, marginBottom: 18 }}>
            <i>Scheduled</i> across every account
          </div>

          <div style={{ border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden', background: th.card }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1.4fr 90px 100px 100px 110px 80px', alignItems: 'center', gap: 12, padding: '12px 18px', borderBottom: `1px solid ${th.line}`, fontFamily: th.mono, fontSize: 10, letterSpacing: 1, color: th.muted }}>
              <div>NAME</div><div>TYPE</div><div>FREQ</div><div>NEXT</div><div style={{ textAlign: 'right' }}>AMOUNT</div><div style={{ textAlign: 'right' }}>AUTO</div>
            </div>
            {LEDGER.recurringTemplates.map((t, i) => {
              const isInc = t.type === 'income';
              const amt = t.amount == null ? '—' : 'S$' + t.amount.toLocaleString(undefined, { maximumFractionDigits: 2 });
              return (
                <div key={t.id} style={{ display: 'grid', gridTemplateColumns: '1.4fr 90px 100px 100px 110px 80px', alignItems: 'center', gap: 12, padding: '14px 18px', borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
                  <div>
                    <div style={{ fontSize: 14, fontWeight: 500 }}>{t.name}</div>
                    <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, marginTop: 2 }}>{t.id}{t.splits ? ` · ${t.splits.length} splits` : ''}</div>
                  </div>
                  <div>
                    <span style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 0.6, padding: '2px 7px', borderRadius: 4,
                      background: t.type === 'income' ? `${th.pos}1f` : t.type === 'transfer' ? `${th.accent}1f` : th.paperAlt,
                      color: t.type === 'income' ? th.pos : t.type === 'transfer' ? th.accent : th.ink2 }}>{t.type.toUpperCase()}</span>
                  </div>
                  <div style={{ fontSize: 12, color: th.ink2 }}>{t.frequency} · {t.dayOfMonth}</div>
                  <div style={{ fontSize: 12, color: th.ink2 }}>{t.nextRun}</div>
                  <div style={{ textAlign: 'right', fontFamily: th.body, fontSize: 14, fontWeight: 500, color: isInc ? th.pos : th.ink }}>
                    {isInc ? '+' : t.amount == null ? '' : '−'}{amt}
                  </div>
                  <div style={{ textAlign: 'right' }}>
                    <div style={{ display: 'inline-block', width: 32, height: 18, borderRadius: 9, background: t.autoPost ? th.accent : th.paperAlt, position: 'relative' }}>
                      <div style={{ position: 'absolute', top: 2, [t.autoPost ? 'right' : 'left']: 2, width: 14, height: 14, borderRadius: 7, background: '#fff', boxShadow: '0 1px 2px rgba(0,0,0,0.15)' }}/>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Right — splits panel */}
        <div>
          <SchemaChip th={th} label="recurring_splits"/>
          <div style={{ fontFamily: th.display, fontSize: 30, letterSpacing: -0.6, marginTop: 10, marginBottom: 6 }}>
            <i>Splits</i> · Acme salary
          </div>
          <div style={{ fontSize: 13, color: th.muted, marginBottom: 16 }}>One inbound salary → three outbound destinations.</div>

          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 18, marginBottom: 14 }}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, marginBottom: 14 }}>
              <div style={{ fontFamily: th.display, fontSize: 36, letterSpacing: -0.8 }}>S$5,800</div>
              <div style={{ fontFamily: th.mono, fontSize: 11, color: th.muted }}>monthly · day 25</div>
            </div>
            <StackedBar
              slices={LEDGER.recurringTemplates[0].splits.map((s, i) => ({
                value: s.pct, color: i === 0 ? th.accent : i === 1 ? th.warn : th.pos,
              }))}
              width={340} height={14} radius={7}/>

            <div style={{ marginTop: 18, display: 'flex', flexDirection: 'column', gap: 10 }}>
              {LEDGER.recurringTemplates[0].splits.map((s, i) => {
                const dot = i === 0 ? th.accent : i === 1 ? th.warn : th.pos;
                const amount = 5800 * s.pct / 100;
                return (
                  <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                    <span style={{ width: 10, height: 10, borderRadius: 5, background: dot }}/>
                    <div style={{ flex: 1 }}>
                      <div style={{ fontSize: 13, fontWeight: 500 }}>{s.account}</div>
                      <div style={{ fontSize: 11, color: th.muted, marginTop: 1 }}>{s.label}</div>
                    </div>
                    <div style={{ fontFamily: th.mono, fontSize: 12, color: th.muted, marginRight: 8 }}>{s.pct}%</div>
                    <div style={{ fontFamily: th.body, fontSize: 14, fontWeight: 500, minWidth: 80, textAlign: 'right' }}>S${amount.toLocaleString(undefined, { maximumFractionDigits: 0 })}</div>
                  </div>
                );
              })}
            </div>
          </div>

          <div style={{ padding: 14, background: th.paperAlt, borderRadius: 10, fontSize: 12, color: th.ink2, lineHeight: 1.5 }}>
            Each row has either <span style={{ fontFamily: th.mono }}>amount_pct</span> <i>or</i> <span style={{ fontFamily: th.mono }}>amount_abs</span> — never both. CHECK constraint enforces it. When the template runs, three transactions are inserted, not one.
          </div>
        </div>
      </div>
    </WebShell>
  );
}

// ─────────────────────────────────────────────────────────────
// 5 · Exchange rates + sync log (combined "Admin" page)
// ─────────────────────────────────────────────────────────────
function WebAdminPanel({ th }) {
  // Build a table grouped by date
  const byDate = {};
  LEDGER.exchangeRates.forEach((r) => { (byDate[r.date] = byDate[r.date] || []).push(r); });
  const dates = Object.keys(byDate).sort().reverse();

  return (
    <WebShell th={th} active="settings" title="System" sub="Exchange rates · device sync · low-level data state"
      actions={<div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, border: `1px solid ${th.line}`, borderRadius: 18, fontSize: 13 }}>Refresh now</div>}>
      <div style={{ padding: 32, display: 'grid', gridTemplateColumns: '1.4fr 1fr', gap: 28 }}>
        {/* Exchange rates */}
        <div>
          <SchemaChip th={th} label="exchange_rates"/>
          <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.5, marginTop: 10, marginBottom: 4 }}>
            <i>Rate book</i> · what fixed the past
          </div>
          <div style={{ fontSize: 12, color: th.muted, marginBottom: 16 }}>
            Each transaction's <span style={{ fontFamily: th.mono }}>exchange_rate</span> reads from this table at import time and never changes after.
          </div>

          <div style={{ border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden', background: th.card }}>
            <div style={{ display: 'grid', gridTemplateColumns: '120px repeat(4, 1fr) 80px', alignItems: 'center', gap: 12, padding: '12px 18px', borderBottom: `1px solid ${th.line}`, fontFamily: th.mono, fontSize: 10, letterSpacing: 1, color: th.muted }}>
              <div>DATE</div>
              <div style={{ textAlign: 'right' }}>JPY → SGD</div>
              <div style={{ textAlign: 'right' }}>CNY → SGD</div>
              <div style={{ textAlign: 'right' }}>USD → SGD</div>
              <div style={{ textAlign: 'right' }}>EUR → SGD</div>
              <div style={{ textAlign: 'right' }}>SOURCE</div>
            </div>
            {dates.slice(0, 8).map((d, i) => {
              const get = (c) => byDate[d].find(r => r.currency === c);
              const jpy = get('JPY'); const cny = get('CNY'); const usd = get('USD'); const eur = get('EUR');
              const source = (jpy || cny || usd || eur)?.source || '—';
              return (
                <div key={d} style={{ display: 'grid', gridTemplateColumns: '120px repeat(4, 1fr) 80px', alignItems: 'center', gap: 12, padding: '11px 18px', borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
                  <div style={{ fontFamily: th.mono, fontSize: 12, color: th.ink2 }}>{d}</div>
                  <div style={{ textAlign: 'right', fontFamily: th.mono, fontSize: 12 }}>{jpy ? jpy.rate.toFixed(5) : <span style={{ color: th.muted }}>—</span>}</div>
                  <div style={{ textAlign: 'right', fontFamily: th.mono, fontSize: 12 }}>{cny ? cny.rate.toFixed(5) : <span style={{ color: th.muted }}>—</span>}</div>
                  <div style={{ textAlign: 'right', fontFamily: th.mono, fontSize: 12 }}>{usd ? usd.rate.toFixed(5) : <span style={{ color: th.muted }}>—</span>}</div>
                  <div style={{ textAlign: 'right', fontFamily: th.mono, fontSize: 12 }}>{eur ? eur.rate.toFixed(5) : <span style={{ color: th.muted }}>—</span>}</div>
                  <div style={{ textAlign: 'right', fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.4 }}>{source.toUpperCase()}</div>
                </div>
              );
            })}
          </div>

          {/* Trendlet */}
          <div style={{ marginTop: 14, padding: 14, background: th.card, border: `1px solid ${th.line}`, borderRadius: 10 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8 }}>
              <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.8 }}>JPY → SGD · LAST 8 DAYS</div>
              <div style={{ fontFamily: th.mono, fontSize: 11, color: th.ink2 }}>0.00872 today · ±0.4%</div>
            </div>
            <Sparkline values={[8.76,8.74,8.68,8.73,8.71,8.71,8.69,8.72]} width={520} height={36} color={th.accent}/>
          </div>
        </div>

        {/* Sync log */}
        <div>
          <SchemaChip th={th} label="sync_log"/>
          <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.5, marginTop: 10, marginBottom: 4 }}>
            <i>Devices</i> reading this ledger
          </div>
          <div style={{ fontSize: 12, color: th.muted, marginBottom: 16 }}>
            Each device only pulls transactions newer than the last <span style={{ fontFamily: th.mono }}>txn_id</span> it saw — incremental sync.
          </div>

          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden' }}>
            {LEDGER.devices.map((d, i) => (
              <div key={d.id} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: 16, borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
                <div style={{ width: 36, height: 36, borderRadius: 8, background: th.paperAlt, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink2 }}>
                  <Icon name={d.id.includes('iphone') ? 'wallet' : d.id.includes('mac') ? 'doc' : d.id.includes('ipad') ? 'menu' : 'cog'} size={16}/>
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <div style={{ fontSize: 14, fontWeight: 500 }}>{d.name}</div>
                    {d.current === 1 && <span style={{ fontFamily: th.mono, fontSize: 9, color: th.pos, letterSpacing: 0.6, padding: '2px 6px', background: `${th.pos}18`, borderRadius: 4 }}>● THIS DEVICE</span>}
                  </div>
                  <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, marginTop: 4, letterSpacing: 0.3 }}>
                    last_txn = {d.txn} · synced {d.last}
                  </div>
                </div>
                <div style={{ fontFamily: th.mono, fontSize: 11, color: th.muted }}>{d.id}</div>
              </div>
            ))}
          </div>

          <div style={{ marginTop: 14, padding: 14, background: th.paperAlt, borderRadius: 10, fontSize: 12, color: th.ink2, lineHeight: 1.5 }}>
            Each row keys on <span style={{ fontFamily: th.mono }}>device_id</span> and stores <span style={{ fontFamily: th.mono }}>last_sync_at</span> + <span style={{ fontFamily: th.mono }}>last_txn_id</span>. New devices simply insert a fresh row on first connect.
          </div>
        </div>
      </div>
    </WebShell>
  );
}

// ─────────────────────────────────────────────────────────────
// 6 · Category hierarchy (parent + sub) — schema 6.4
// ─────────────────────────────────────────────────────────────
function WebCategoryTree({ th }) {
  return (
    <WebShell th={th} active="budgets" title="Categories" sub="Two-level hierarchy · parent rolls up its children's totals"
      actions={<div style={{ height: 36, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 6, background: th.ink, color: th.paper, borderRadius: 18, fontSize: 13, fontWeight: 500 }}><Icon name="plus" size={14} stroke={2}/>New category</div>}>
      <div style={{ padding: 32 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 14, paddingBottom: 18, marginBottom: 18, borderBottom: `1px solid ${th.line}` }}>
          <SchemaChip th={th} label="categories"/>
          <div style={{ fontFamily: th.display, fontSize: 32, letterSpacing: -0.7, fontStyle: 'italic' }}>The shape of your spending</div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 14 }}>
          {LEDGER.categoryTree.map((c) => (
            <div key={c.parent} style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 18 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12 }}>
                <CatDot hue={c.hue} size={12}/>
                <div style={{ fontFamily: th.display, fontSize: 22, letterSpacing: -0.3 }}>{c.parent}</div>
                <span style={{ marginLeft: 'auto', fontFamily: th.mono, fontSize: 10, letterSpacing: 0.6, padding: '2px 7px', background: th.paperAlt, color: th.ink2, borderRadius: 4 }}>{c.type.toUpperCase()}</span>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                {c.children.map((s) => (
                  <div key={s} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 0', borderTop: `0.5px dotted ${th.line}` }}>
                    <div style={{ width: 14, height: 1, background: th.line, marginLeft: 4 }}/>
                    <div style={{ fontSize: 13, color: th.ink2 }}>{s}</div>
                    <span style={{ marginLeft: 'auto', fontFamily: th.mono, fontSize: 10, color: th.muted }}>parent_name = "{c.parent}"</span>
                  </div>
                ))}
                <div style={{ marginTop: 6, fontFamily: th.mono, fontSize: 10, color: th.muted, padding: '4px 4px' }}>+ new subcategory</div>
              </div>
            </div>
          ))}
        </div>

        <div style={{ marginTop: 22, padding: 16, background: th.paperAlt, borderRadius: 10, fontSize: 12, color: th.ink2, lineHeight: 1.5 }}>
          Deleting a category sets every transaction's <span style={{ fontFamily: th.mono }}>category_id</span> to NULL (ON DELETE SET NULL) — your history is preserved as "uncategorized", never destroyed.
        </div>
      </div>
    </WebShell>
  );
}

Object.assign(window, {
  WebLedgerAdmin, WebPendingReview, WebCounterparties,
  WebRecurringTemplates, WebAdminPanel, WebCategoryTree,
});
