'use client';

import { useParams } from 'next/navigation';
import Link from 'next/link';
import { useTweaks } from '@/components/TweaksContext';
import { Icon, Money, Sparkline, MerchantGlyph } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { MOCK, fmtMoneyShort, catById } from '@/lib/data';
import styles from './account-detail.module.css';

export default function AccountDetailPage() {
  const { theme: th } = useTweaks();
  const params = useParams();
  const accountId = params.id as string;
  const account = MOCK.accounts.find(a => a.id === accountId) || MOCK.accounts[0];
  const txs = MOCK.transactions.filter(t => t.account === account.id);

  return (
    <MobilePage
      header={
        <ScreenHeader
          title={account.name}
          back={true}
        />
      }
    >
      <div className={styles.body}>
        <div className={styles.breadcrumb}>
          <Link href="/accounts" className={styles.breadcrumbLink}>Accounts</Link>
          <Icon name="chev" size={11}/>
          <span className={styles.breadcrumbCurrent}>{account.name}</span>
        </div>

        <div className={styles.heroCard} style={{ background: account.color }}>
          <div className={styles.heroBlob}/>
          <div>
            <div className={styles.heroLabel}>Available balance</div>
            <div className={styles.heroBalance}>
              <Money value={account.balance} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
            </div>
            <div className={styles.heroStats}>
              <div><div className={styles.heroStatLabel}>IN · 30D</div><div className={styles.heroStatValue}>{fmtMoneyShort(5800, th.currency)}</div></div>
              <div><div className={styles.heroStatLabel}>OUT · 30D</div><div className={styles.heroStatValue}>{fmtMoneyShort(1850, th.currency)}</div></div>
              <div><div className={styles.heroStatLabel}>NET</div><div className={styles.heroStatValue} style={{ color: '#9bb89b' }}>+{fmtMoneyShort(3950, th.currency)}</div></div>
            </div>
          </div>
          <div className={styles.heroChartCol}>
            <Sparkline values={[3200,3400,3300,3700,3650,4100,4050,4300,4250,4400,4500,4450,4218]} width={420} height={120} color="#fff" stroke={1.8} fillOpacity={0.16}/>
          </div>
        </div>

        <div className={styles.detailGrid}>
          <div className={styles.txCard}>
            <div className={styles.txHeader}>
              <div className={styles.txHeaderTitle}>All transactions · {txs.length}</div>
              <div className={styles.txFilter}><Icon name="filter" size={12}/>Filter</div>
            </div>
            {txs.slice(0, 6).map((tx, i) => {
              const cat = catById(tx.category);
              const inc = tx.amount > 0;
              return (
                <div key={tx.id} className={i ? `${styles.txRow} ${styles.txRowDivider}` : styles.txRow}>
                  <MerchantGlyph name={tx.merchant} size={32} hue={cat.hue}/>
                  <div className={styles.txInfo}>
                    <div className={styles.txMerchant}>{tx.merchant}</div>
                    <div className={styles.txMeta}>{tx.date.slice(5).replace('-','/')} · {cat.name || 'Income'}</div>
                  </div>
                  <Money value={tx.amount} currency={th.currency} signed={inc} style={{ fontFamily: th.mono, fontSize: 13, fontWeight: 600, color: inc ? 'var(--pos)' : 'var(--ink)' }}/>
                </div>
              );
            })}
          </div>

          <div className={styles.detailsCard}>
            <div className={styles.detailsLabel}>ACCOUNT DETAILS</div>
            {[
              ['Type', account.type.charAt(0).toUpperCase() + account.type.slice(1)],
              ['Number', `•••• ${account.last4}`],
              ['Routing', '021000021'],
              ['Institution', 'Chase Bank, N.A.'],
              ['Currency', th.currency],
              ['Last sync', '2 min ago'],
              ['Linked since', 'Jan 2024'],
            ].map(([l, v], i) => (
              <div key={l} className={i ? `${styles.detailRow} ${styles.detailRowDivider}` : styles.detailRow}>
                <span className={styles.detailKey}>{l}</span>
                <span className={styles.detailValue}>{v}</span>
              </div>
            ))}
            <div className={styles.autoCat}>
              <Icon name="sync" size={12}/>Auto-categorize: on
            </div>
          </div>
        </div>
      </div>
    </MobilePage>
  );
}