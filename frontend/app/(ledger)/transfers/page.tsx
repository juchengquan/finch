'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { LEDGER } from '@/lib/data';
import styles from './transfers.module.css';

export default function TransfersPage() {
  const { theme: th } = useTweaks();
  const tg = LEDGER.transferGroups[1];

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Transfers"
          trailing={<IconButton icon="dots"/>}
        />
      }
    >
      <div className={styles.page}>
        <div className={styles.head}>
          <SchemaChip label="transfer_groups"/>
          <div className={styles.lead}>You transferred</div>
          <div className={styles.amount}>
            S$80,000<span className={styles.amountCents}>.00</span>
          </div>
          <div className={styles.received}>
            → ¥422,728 received
          </div>
          <div className={styles.rateLock}>
            <Icon name="check" size={12} style={{ color: th.pos }} stroke={2}/>
            RATE LOCKED @ 5.2841 · MON MAY 18
          </div>
        </div>

        <div className={styles.card}>
          <div className={`${styles.legRow} ${styles.legRowDivider}`}>
            <div className={styles.legIcon} style={{ background: `${th.neg}1a`, color: th.neg }}>
              <Icon name="arrow-u" size={16} stroke={2}/>
            </div>
            <div className={styles.legBody}>
              <div className={styles.legLabel}>FROM · PERSONAL LEDGER</div>
              <div className={styles.legAccount}>{tg.fromAccount}</div>
            </div>
            <div className={styles.legAmount} style={{ color: th.neg }}>−S$80,000.00</div>
          </div>
          <div className={styles.legRow}>
            <div className={styles.legIcon} style={{ background: `${th.pos}1a`, color: th.pos }}>
              <Icon name="arrow-d" size={16} stroke={2}/>
            </div>
            <div className={styles.legBody}>
              <div className={styles.legLabel}>TO · SIDE STUDIO LEDGER</div>
              <div className={styles.legAccount}>{tg.toAccount}</div>
            </div>
            <div className={styles.legAmount} style={{ color: th.pos }}>+¥422,728</div>
          </div>
        </div>

        <div className={styles.detail}>
          {[
            ['transfer_group_id', tg.id],
            ['amount_base',       'S$80,000.00 (locked)'],
            ['exchange_rate',     '5.2841 SGD→CNY'],
            ['from_currency',    'SGD'],
            ['to_currency',       'CNY'],
            ['notes',             tg.notes],
          ].map((r, i) => (
            <div key={r[0]} className={`${styles.detailRow}${i ? ` ${styles.detailRowDivider}` : ''}`}>
              <span className={styles.detailKey}>{r[0]}</span>
              <span className={styles.detailValue}>{r[1]}</span>
            </div>
          ))}
        </div>

        <div className={styles.note}>
          The exchange rate is locked at import time. Both transactions share <span className={styles.noteCode}>amount_base</span> so reports across ledgers stay consistent.
        </div>
      </div>
    </MobilePage>
  );
}
