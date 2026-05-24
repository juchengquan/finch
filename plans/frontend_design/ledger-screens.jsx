// Mobile screens that surface concepts from the SQLite schema:
// · Ledger switcher (modal)
// · Pending review queue
// · Transfer detail (transfer_groups + locked FX)
// · Counterparties manager
// · Recurring template editor w/ splits
// · Multi-currency transaction detail

// Helper — schema-style chip
function SchemaChip({ th, label }) {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', height: 18, padding: '0 6px',
      fontFamily: th.mono, fontSize: 9, letterSpacing: 0.5, color: th.muted,
      border: `1px solid ${th.line}`, borderRadius: 4 }}>{label}</span>
  );
}

// ─────────────────────────────────────────────────────────────
// 1 · Ledger switcher — bottom sheet pattern
// ─────────────────────────────────────────────────────────────
function ScreenLedgerSwitch({ th }) {
  return (
    <div style={{ height: '100%', background: 'rgba(20,18,16,0.45)', color: th.ink, fontFamily: th.body, position: 'relative' }}>
      {/* Faded background hint */}
      <div style={{ paddingTop: STATUS_PAD + 8, padding: '64px 20px 0', opacity: 0.35 }}>
        <ScreenHeader th={th} title="Accounts"/>
        <div style={{ padding: '0 4px' }}>
          <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1.2, textTransform: 'uppercase' }}>Net worth · all accounts</div>
          <div style={{ fontFamily: th.display, fontSize: 52, letterSpacing: -2, lineHeight: 1, marginTop: 6 }}>$32,926.32</div>
        </div>
      </div>

      {/* Sheet */}
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, background: th.paper,
        borderTopLeftRadius: 24, borderTopRightRadius: 24, padding: '12px 20px 28px',
        boxShadow: '0 -10px 40px rgba(0,0,0,0.15)' }}>
        <div style={{ width: 44, height: 4, borderRadius: 2, background: th.line, margin: '4px auto 18px' }}/>
        <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 4 }}>
          <div style={{ fontFamily: th.display, fontSize: 26, fontStyle: 'italic', letterSpacing: -0.4 }}>Switch ledger</div>
          <SchemaChip th={th} label="ledgers"/>
        </div>
        <div style={{ fontSize: 12, color: th.muted, marginBottom: 18 }}>Each ledger is an isolated set of books. Records never cross.</div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {LEDGER.ledgers.map((l) => {
            const isActive = l.id === LEDGER.active;
            return (
              <div key={l.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 14,
                background: isActive ? th.card : 'transparent',
                border: `1px solid ${isActive ? th.ink : th.line}`, borderRadius: 14 }}>
                <div style={{ width: 38, height: 38, borderRadius: 8, background: l.color, color: '#fff',
                  fontFamily: th.display, fontSize: 22, fontStyle: 'italic',
                  display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  {l.name.charAt(0)}
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                    <div style={{ fontSize: 15, fontWeight: 500 }}>{l.name}</div>
                    {l.isDefault === 1 && <span style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 0.6 }}>DEFAULT</span>}
                  </div>
                  <div style={{ fontSize: 11, color: th.muted, marginTop: 2 }}>{l.tagline}</div>
                  <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, marginTop: 4, letterSpacing: 0.3 }}>
                    {l.accounts} accts · {l.txns.toLocaleString()} txns · base {l.base}
                  </div>
                </div>
                {isActive ? (
                  <div style={{ width: 22, height: 22, borderRadius: 11, background: th.ink, color: th.paper, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="check" size={12} stroke={2.2}/></div>
                ) : (
                  <Icon name="chev" size={14} style={{ color: th.muted }}/>
                )}
              </div>
            );
          })}
          <div style={{ marginTop: 4, height: 48, borderRadius: 12, border: `1px dashed ${th.line}`,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, color: th.muted, fontSize: 13 }}>
            <Icon name="plus" size={14}/>New ledger
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 2 · Pending review queue
// ─────────────────────────────────────────────────────────────
function ScreenPendingReview({ th }) {
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <div style={{ paddingTop: STATUS_PAD + 8 }}>
          <ScreenHeader th={th} title="Pending"
            trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="filter" size={16}/></div>}/>
        </div>

        {/* Hero */}
        <div style={{ padding: '0 24px 20px' }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 4 }}>
            <SchemaChip th={th} label="status = pending"/>
            <span style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.6 }}>EXCLUDED FROM REPORTS</span>
          </div>
          <div style={{ fontFamily: th.display, fontSize: 44, letterSpacing: -1.6, lineHeight: 1, marginTop: 6 }}>
            {LEDGER.pending.length} <span style={{ fontStyle: 'italic', color: th.muted }}>items</span>
          </div>
          <div style={{ fontSize: 13, color: th.ink2, marginTop: 6 }}>
            Confirm them to flow into your reports. Or cancel to ignore.
          </div>
        </div>

        {/* Bulk action bar */}
        <div style={{ margin: '0 20px 14px', display: 'flex', gap: 8 }}>
          <div style={{ flex: 1, height: 38, background: th.ink, color: th.paper, borderRadius: 19,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, fontSize: 12, fontWeight: 500 }}>
            <Icon name="check" size={14}/>Confirm all
          </div>
          <div style={{ width: 38, height: 38, border: `1px solid ${th.line}`, borderRadius: 19,
            display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.muted }}>
            <Icon name="x" size={14}/>
          </div>
        </div>

        {/* Items */}
        <div style={{ padding: '0 20px' }}>
          {LEDGER.pending.map((p, i) => {
            const inc = p.amount > 0;
            const isFx = p.currency !== 'SGD';
            return (
              <div key={p.id} style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 16, marginBottom: 10 }}>
                <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
                  <MerchantGlyph name={p.merchant} size={36} hue={(i*60) % 360}/>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8, alignItems: 'baseline' }}>
                      <div style={{ fontSize: 14, fontWeight: 500 }}>{p.merchant}</div>
                      <div style={{ fontFamily: th.body, fontSize: 15, fontWeight: 500, color: inc ? th.pos : th.ink, fontVariantNumeric: 'tabular-nums' }}>
                        {inc ? '+' : ''}{p.currency === 'JPY' ? '¥' : 'S$'}{Math.abs(p.amount).toLocaleString()}
                      </div>
                    </div>
                    <div style={{ fontSize: 11, color: th.muted, marginTop: 2, display: 'flex', alignItems: 'center', gap: 6 }}>
                      {p.account} · {p.date.slice(5).replace('-','/')}
                      {isFx && <span style={{ fontFamily: th.mono, color: th.warn, fontSize: 10 }}>· FX</span>}
                    </div>
                    <div style={{ marginTop: 10, padding: '8px 10px', background: th.paperAlt, borderRadius: 8,
                      fontSize: 12, color: th.ink2, display: 'flex', alignItems: 'center', gap: 8 }}>
                      <Icon name="sparkle" size={13} style={{ color: th.accent, flexShrink: 0 }}/>{p.reason}
                    </div>
                  </div>
                </div>
                {/* Inline actions */}
                <div style={{ display: 'flex', gap: 6, marginTop: 12 }}>
                  <div style={{ flex: 1, height: 32, background: th.ink, color: th.paper, borderRadius: 16,
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, fontSize: 12, fontWeight: 500 }}>
                    <Icon name="check" size={12} stroke={2}/>Confirm
                  </div>
                  <div style={{ height: 32, padding: '0 14px', border: `1px solid ${th.line}`, borderRadius: 16,
                    display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, color: th.ink }}>
                    Edit
                  </div>
                  <div style={{ height: 32, width: 32, border: `1px solid ${th.line}`, borderRadius: 16,
                    display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.muted }}>
                    <Icon name="x" size={12}/>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>
      <MobileTabBar th={th} active="more"/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 3 · Transfer detail — both sides of a transfer_group
// ─────────────────────────────────────────────────────────────
function ScreenTransferDetail({ th }) {
  const tg = LEDGER.transferGroups[1]; // SGD → CNY cross-ledger
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ paddingTop: STATUS_PAD + 8 }}>
        <ScreenHeader th={th} title="Transfer" back={true} trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="dots" size={16}/></div>}/>
      </div>

      {/* Hero — locked FX */}
      <div style={{ padding: '0 24px 22px', textAlign: 'center' }}>
        <SchemaChip th={th} label="transfer_groups"/>
        <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 22, color: th.muted, marginTop: 14 }}>You transferred</div>
        <div style={{ fontFamily: th.display, fontSize: 52, letterSpacing: -1.8, marginTop: 4 }}>
          S$80,000<span style={{ fontSize: 28, color: th.muted, letterSpacing: -0.5 }}>.00</span>
        </div>
        <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 18, color: th.ink2, marginTop: 2 }}>
          → ¥422,728 received
        </div>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, marginTop: 14,
          padding: '6px 12px', borderRadius: 14, background: th.paperAlt, fontFamily: th.mono, fontSize: 10, letterSpacing: 0.6, color: th.ink2 }}>
          <Icon name="check" size={12} style={{ color: th.pos }} stroke={2}/>
          RATE LOCKED @ 5.2841 · MON MAY 18
        </div>
      </div>

      {/* Two sides */}
      <div style={{ padding: '0 20px' }}>
        <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 0, marginBottom: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 16, borderBottom: `1px dashed ${th.line}` }}>
            <div style={{ width: 32, height: 32, borderRadius: 16, background: `${th.neg}1a`, color: th.neg, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Icon name="arrow-u" size={16} stroke={2}/>
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1 }}>FROM · PERSONAL LEDGER</div>
              <div style={{ fontSize: 14, fontWeight: 500, marginTop: 2 }}>{tg.fromAccount}</div>
            </div>
            <div style={{ fontFamily: th.body, fontSize: 16, fontWeight: 500, color: th.neg, fontVariantNumeric: 'tabular-nums' }}>−S$80,000.00</div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 16 }}>
            <div style={{ width: 32, height: 32, borderRadius: 16, background: `${th.pos}1a`, color: th.pos, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Icon name="arrow-d" size={16} stroke={2}/>
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1 }}>TO · SIDE STUDIO LEDGER</div>
              <div style={{ fontSize: 14, fontWeight: 500, marginTop: 2 }}>{tg.toAccount}</div>
            </div>
            <div style={{ fontFamily: th.body, fontSize: 16, fontWeight: 500, color: th.pos, fontVariantNumeric: 'tabular-nums' }}>+¥422,728</div>
          </div>
        </div>

        {/* Schema details */}
        <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: '4px 16px' }}>
          {[
            ['transfer_group_id', tg.id],
            ['amount_base',       'S$80,000.00 (locked)'],
            ['exchange_rate',     '5.2841 SGD→CNY'],
            ['from_currency',     'SGD'],
            ['to_currency',       'CNY'],
            ['notes',             tg.notes],
          ].map((r, i) => (
            <div key={r[0]} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px 0', borderTop: i ? `0.5px solid ${th.line}` : 'none', fontSize: 13 }}>
              <span style={{ fontFamily: th.mono, fontSize: 11, color: th.muted, letterSpacing: 0.4 }}>{r[0]}</span>
              <span style={{ textAlign: 'right' }}>{r[1]}</span>
            </div>
          ))}
        </div>

        <div style={{ marginTop: 14, fontSize: 11, color: th.muted, lineHeight: 1.5, padding: '0 4px' }}>
          The exchange rate is locked at import time. Both transactions share <span style={{ fontFamily: th.mono, color: th.ink2 }}>amount_base</span> so reports across ledgers stay consistent.
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 4 · Counterparties manager
// ─────────────────────────────────────────────────────────────
function ScreenCounterparties({ th }) {
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <div style={{ paddingTop: STATUS_PAD + 8 }}>
          <ScreenHeader th={th} title="Merchants" trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="plus" size={16}/></div>}/>
        </div>

        {/* Stats strip */}
        <div style={{ padding: '0 24px 18px' }}>
          <SchemaChip th={th} label="counterparties"/>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 14, marginTop: 8 }}>
            <div>
              <div style={{ fontFamily: th.display, fontSize: 40, letterSpacing: -1.4, lineHeight: 1 }}>{LEDGER.counterparties.length}</div>
              <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1, marginTop: 4 }}>STANDARDISED</div>
            </div>
            <div style={{ width: 1, height: 32, background: th.line }}/>
            <div>
              <div style={{ fontFamily: th.display, fontSize: 40, letterSpacing: -1.4, lineHeight: 1, color: th.warn }}>
                {LEDGER.counterparties.filter(c=>!c.verified).length}
              </div>
              <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1, marginTop: 4 }}>UNVERIFIED</div>
            </div>
          </div>
          <div style={{ fontSize: 12, color: th.muted, marginTop: 10, lineHeight: 1.5 }}>
            Banks spell the same merchant a dozen ways. Aliases unify them into one canonical name.
          </div>
        </div>

        {/* Search */}
        <div style={{ margin: '0 20px 14px', height: 38, borderRadius: 19, background: th.paperAlt, display: 'flex', alignItems: 'center', gap: 10, padding: '0 14px', color: th.muted, fontSize: 13 }}>
          <Icon name="search" size={14}/>Search merchants & aliases…
        </div>

        {/* Filter pills */}
        <div style={{ padding: '0 20px 14px', display: 'flex', gap: 6 }}>
          {[['All', true], ['Unverified', false], ['Food', false], ['Transport', false]].map(([l, on]) => (
            <div key={l} style={{ padding: '6px 12px', borderRadius: 6, fontSize: 11, fontWeight: 500,
              background: on ? th.ink : 'transparent', color: on ? th.paper : th.muted, border: on ? 'none' : `1px solid ${th.line}` }}>{l}</div>
          ))}
        </div>

        {/* List */}
        <div style={{ padding: '0 20px' }}>
          {LEDGER.counterparties.map((c, i) => (
            <div key={c.id} style={{ display: 'flex', alignItems: 'flex-start', gap: 12,
              padding: '14px 0', borderTop: i ? `0.5px solid ${th.line}` : 'none' }}>
              <MerchantGlyph name={c.name} size={40} hue={c.hue}/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 8 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <div style={{ fontSize: 14, fontWeight: 500 }}>{c.name}</div>
                    {!c.verified && (
                      <span style={{ fontFamily: th.mono, fontSize: 9, color: th.warn, letterSpacing: 0.6, padding: '2px 6px', border: `1px solid ${th.warn}66`, borderRadius: 4 }}>UNVERIFIED</span>
                    )}
                  </div>
                  <div style={{ fontFamily: th.mono, fontSize: 11, color: th.muted }}>{c.txCount}×</div>
                </div>
                <div style={{ fontSize: 11, color: th.muted, marginTop: 4 }}>
                  {c.category} <span style={{ margin: '0 5px' }}>·</span>
                  <span style={{ fontFamily: th.mono, fontSize: 10, color: th.ink2 }}>aliases:</span>
                </div>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginTop: 6 }}>
                  {c.aliases.map((a) => (
                    <span key={a} style={{ fontFamily: th.mono, fontSize: 10, padding: '2px 7px', background: th.paperAlt, color: th.ink2, borderRadius: 4, letterSpacing: 0.2 }}>{a}</span>
                  ))}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
      <MobileTabBar th={th} active="more"/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 5 · Recurring template editor — with splits visible
// ─────────────────────────────────────────────────────────────
function ScreenRecurringTemplate({ th }) {
  const t = LEDGER.recurringTemplates[0]; // salary with splits
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <div style={{ paddingTop: STATUS_PAD + 8 }}>
          <ScreenHeader th={th} title="Recurring" back={true}
            trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink }}><Icon name="dots" size={16}/></div>}/>
        </div>

        {/* Hero */}
        <div style={{ padding: '0 24px 22px' }}>
          <SchemaChip th={th} label="recurring_templates"/>
          <div style={{ fontFamily: th.display, fontSize: 36, letterSpacing: -0.8, lineHeight: 1.1, marginTop: 10 }}>
            <span style={{ fontStyle: 'italic', color: th.muted }}>Every 25th, you receive</span><br/>
            <span style={{ fontSize: 44 }}>S$5,800.00</span>
          </div>
          <div style={{ fontSize: 12, color: th.muted, marginTop: 8 }}>
            from <b style={{ color: th.ink2 }}>Acme</b> — next on May 25 · awaits your confirmation
          </div>
        </div>

        {/* Meta strip */}
        <div style={{ padding: '0 20px', marginBottom: 16 }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
            {[
              ['type',      'income'],
              ['frequency', 'monthly · 25th'],
              ['auto_post', 'false · ask first'],
              ['last_run',  'Apr 25'],
            ].map(([k, v]) => (
              <div key={k} style={{ padding: 12, background: th.card, border: `1px solid ${th.line}`, borderRadius: 10 }}>
                <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 0.6 }}>{k}</div>
                <div style={{ fontSize: 13, fontWeight: 500, marginTop: 2 }}>{v}</div>
              </div>
            ))}
          </div>
        </div>

        {/* Splits panel */}
        <div style={{ padding: '0 20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8, padding: '0 4px' }}>
            <div style={{ fontFamily: th.display, fontSize: 20, fontStyle: 'italic', letterSpacing: -0.2 }}>Splits</div>
            <SchemaChip th={th} label="recurring_splits"/>
          </div>
          <div style={{ fontSize: 12, color: th.muted, padding: '0 4px 10px' }}>
            Salary is split across accounts. Total must equal 100%.
          </div>

          {/* Stacked bar visualization */}
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 14, marginBottom: 10 }}>
            <StackedBar
              slices={t.splits.map((s, i) => ({ value: s.pct, color: i === 0 ? th.accent : i === 1 ? th.warn : th.pos }))}
              width={310} height={12} radius={6}/>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 10, fontFamily: th.mono, fontSize: 10, color: th.muted }}>
              <span>0%</span><span>50%</span><span>100%</span>
            </div>
          </div>

          {/* Per-split rows */}
          {t.splits.map((s, i) => {
            const dot = i === 0 ? th.accent : i === 1 ? th.warn : th.pos;
            const amount = 5800 * s.pct / 100;
            return (
              <div key={i} style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 14, marginBottom: 8 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                  <div style={{ width: 8, height: 36, borderRadius: 4, background: dot }}/>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                      <div style={{ fontSize: 14, fontWeight: 500 }}>{s.account}</div>
                      <div style={{ fontFamily: th.body, fontSize: 14, fontWeight: 500 }}>S${amount.toLocaleString(undefined, { maximumFractionDigits: 0 })}</div>
                    </div>
                    <div style={{ fontSize: 11, color: th.muted, marginTop: 2 }}>{s.label} · <span style={{ fontFamily: th.mono, fontSize: 10 }}>amount_pct = {s.pct}</span></div>
                  </div>
                </div>
              </div>
            );
          })}

          <div style={{ marginTop: 4, height: 44, borderRadius: 12, border: `1px dashed ${th.line}`,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, color: th.muted, fontSize: 12 }}>
            <Icon name="plus" size={14}/>Add split rule
          </div>
        </div>

        {/* Footer action */}
        <div style={{ padding: '24px 20px 8px' }}>
          <div style={{ height: 50, borderRadius: 25, background: th.ink, color: th.paper, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, fontWeight: 500 }}>
            Save template
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 6 · Multi-currency transaction detail
// ─────────────────────────────────────────────────────────────
function ScreenFxTransaction({ th }) {
  const tx = LEDGER.fxTx;
  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ paddingTop: STATUS_PAD + 8 }}>
        <ScreenHeader th={th} title="" back={true} trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Icon name="dots" size={16}/></div>}/>
      </div>

      {/* Hero — original + base side by side */}
      <div style={{ padding: '0 24px 14px', textAlign: 'center' }}>
        <MerchantGlyph name={tx.merchant} size={56} hue={12}/>
        <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 20, color: th.muted, marginTop: 16 }}>You spent at</div>
        <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.5, marginTop: 2 }}>{tx.merchant}</div>

        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 18, marginTop: 22 }}>
          <div>
            <div style={{ fontFamily: th.mono, fontSize: 9, letterSpacing: 1, color: th.muted, marginBottom: 4 }}>ORIGINAL</div>
            <div style={{ fontFamily: th.display, fontSize: 44, letterSpacing: -1.4, lineHeight: 1, color: th.ink }}>¥3,820</div>
            <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, marginTop: 4 }}>amount · JPY</div>
          </div>
          <div style={{ width: 1, height: 60, background: th.line }}/>
          <div>
            <div style={{ fontFamily: th.mono, fontSize: 9, letterSpacing: 1, color: th.muted, marginBottom: 4 }}>BASE · LOCKED</div>
            <div style={{ fontFamily: th.display, fontSize: 44, letterSpacing: -1.4, lineHeight: 1, color: th.accent }}>S$33.31</div>
            <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, marginTop: 4 }}>amount_base · SGD</div>
          </div>
        </div>

        <div style={{ marginTop: 14, fontSize: 12, color: th.ink2, fontStyle: 'italic', fontFamily: th.display }}>
          Locked at 0.008721 on May 13 — preserved forever, even if the rate moves.
        </div>
      </div>

      {/* Schema row */}
      <div style={{ padding: '0 20px', marginTop: 8 }}>
        <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: '4px 16px' }}>
          {[
            ['ledger',             'Personal · base SGD'],
            ['account',            tx.account],
            ['category',           'Food & Dining › Restaurants'],
            ['currency',           'JPY'],
            ['exchange_rate',      '0.008721'],
            ['exchange_rate_date', 'May 13, 2026 · ECB'],
            ['status',             'confirmed'],
            ['source',             'csv import'],
          ].map((r, i) => (
            <div key={r[0]} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '11px 0', borderTop: i ? `0.5px solid ${th.line}` : 'none', fontSize: 13 }}>
              <span style={{ fontFamily: th.mono, fontSize: 11, color: th.muted, letterSpacing: 0.4 }}>{r[0]}</span>
              <span style={{ textAlign: 'right' }}>{r[1]}</span>
            </div>
          ))}
        </div>

        {/* FX history sparkline */}
        <div style={{ marginTop: 14, padding: 14, background: th.card, border: `1px solid ${th.line}`, borderRadius: 14 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8 }}>
            <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.8 }}>JPY → SGD · LAST 30 DAYS</div>
            <div style={{ fontFamily: th.mono, fontSize: 11, color: th.ink2 }}>0.00872 today</div>
          </div>
          <Sparkline values={[8.68,8.72,8.74,8.69,8.66,8.71,8.73,8.76,8.74,8.71,8.69,8.68,8.71,8.74,8.72,8.69,8.74,8.76,8.72,8.71,8.68,8.74]} width={310} height={40} color={th.accent}/>
          <div style={{ fontSize: 11, color: th.muted, marginTop: 8, lineHeight: 1.45 }}>
            Your <span style={{ fontFamily: th.mono, color: th.ink2 }}>amount_base</span> stays locked. The chart above is informational only.
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  ScreenLedgerSwitch, ScreenPendingReview, ScreenTransferDetail,
  ScreenCounterparties, ScreenRecurringTemplate, ScreenFxTransaction,
  SchemaChip,
});
