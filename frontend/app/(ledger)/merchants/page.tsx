'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { LEDGER } from '@/lib/data';
import styles from './merchants.module.css';

export default function MerchantsPage() {
  const { theme: th } = useTweaks();

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Merchants"
          trailing={<IconButton icon="plus"/>}
        />
      }
    >
      <div className={styles.page}>
        <div className={styles.head}>
          <SchemaChip label="counterparties"/>
          <div className={styles.stats}>
            <div>
              <div className={styles.statNum}>{LEDGER.counterparties.length}</div>
              <div className={styles.statLabel}>STANDARDISED</div>
            </div>
            <div className={styles.statDivider}/>
            <div>
              <div className={`${styles.statNum} ${styles.statNumWarn}`}>
                {LEDGER.counterparties.filter(c => !c.verified).length}
              </div>
              <div className={styles.statLabel}>UNVERIFIED</div>
            </div>
          </div>
        </div>

        <div className={styles.search}>
          <Icon name="search" size={14}/>Search merchants & aliases…
        </div>

        <div className={styles.list}>
          {LEDGER.counterparties.map((c, i) => (
            <div key={c.id} className={`${styles.row}${i ? ` ${styles.rowDivider}` : ''}`}>
              <div className={styles.avatar} style={{ background: `oklch(0.65 0.2 ${c.hue})` }}>
                {c.name.slice(0, 2).toUpperCase()}
              </div>
              <div className={styles.body}>
                <div className={styles.titleRow}>
                  <div className={styles.nameWrap}>
                    <div className={styles.name}>{c.name}</div>
                    {!c.verified && (
                      <span className={styles.badge} style={{ border: `1px solid ${th.warn}66` }}>UNVERIFIED</span>
                    )}
                  </div>
                  <div className={styles.count}>{c.txCount}×</div>
                </div>
                <div className={styles.category}>
                  {c.category} <span className={styles.dot}>·</span>
                  <span className={styles.aliasLabel}>aliases:</span>
                </div>
                <div className={styles.aliases}>
                  {c.aliases.map((a) => (
                    <span key={a} className={styles.alias}>{a}</span>
                  ))}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </MobilePage>
  );
}
