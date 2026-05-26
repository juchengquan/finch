'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { LEDGER, fmtNative } from '@/lib/data';
import styles from './pending.module.css';

export default function PendingPage() {
  const { theme: th } = useTweaks();

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Pending"
          trailing={<IconButton icon="filter"/>}
        />
      }
    >
      <div className={styles.page}>
        <div className={styles.head}>
          <SchemaChip label="status = pending"/>
          <div className={styles.count}>
            {LEDGER.pending.length} <span className={styles.countUnit}>items</span>
          </div>
          <div className={styles.intro}>
            Confirm them to flow into your reports. Or cancel to ignore.
          </div>
        </div>

        <div className={styles.actions}>
          <button type="button" className={styles.confirmAll}>
            <Icon name="check" size={14}/>Confirm all
          </button>
          <button type="button" aria-label="Dismiss" className={styles.dismiss}>
            <Icon name="x" size={14}/>
          </button>
        </div>

        {LEDGER.pending.map((p, i) => {
          const inc = p.amount > 0;
          const isFx = p.currency !== 'SGD';
          return (
            <div key={p.id} className={styles.card}>
              <div className={styles.cardRow}>
                <div className={styles.avatar} style={{ background: `oklch(0.65 0.2 ${(i * 60) % 360})` }}>
                  {p.merchant.slice(0, 2).toUpperCase()}
                </div>
                <div className={styles.body}>
                  <div className={styles.titleRow}>
                    <div className={styles.merchant}>{p.merchant}</div>
                    <div className={styles.amount} style={{ color: inc ? th.pos : th.ink }}>
                      {fmtNative(p.amount, p.currency, { signed: true })}
                    </div>
                  </div>
                  <div className={styles.meta}>
                    {p.account} · {p.date.slice(5).replace('-', '/')}
                    {isFx && <span className={styles.fx}>· FX</span>}
                  </div>
                  <div className={styles.reason}>
                    <Icon name="sparkle" size={13} style={{ color: th.accent, flexShrink: 0 }}/>{p.reason}
                  </div>
                </div>
              </div>
              <div className={styles.cardActions}>
                <button type="button" className={styles.confirm}>
                  <Icon name="check" size={12} stroke={2}/>Confirm
                </button>
                <button type="button" className={styles.edit}>
                  Edit
                </button>
                <button type="button" aria-label="Cancel" className={styles.cancel}>
                  <Icon name="x" size={12}/>
                </button>
              </div>
            </div>
          );
        })}
      </div>
    </MobilePage>
  );
}
