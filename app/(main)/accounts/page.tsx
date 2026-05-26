'use client';

import Link from 'next/link';
import { useTweaks } from '@/components/TweaksContext';
import { Icon, Money, Card } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { FinchAccordion, FinchAccordionItem, FinchAccordionTrigger, FinchAccordionContent } from '@/components/RadixWrappers';
import { MOCK, fmtMoneyShort } from '@/lib/data';
import styles from './accounts.module.css';

const DEFAULT_OPEN_GROUPS = ['cash', 'credit', 'invest'];

export default function AccountsPage() {
  const { theme: th } = useTweaks();
  const total = MOCK.accounts.reduce((s, a) => s + a.balance, 0);

  const groupedAccounts = MOCK.accountGroups.map((g) => ({ ...g, accounts: MOCK.accounts.filter((a) => a.group === g.id) }));

  return (
    <MobilePage>
      <ScreenHeader
        title="Accounts"
        trailing={<IconButton icon="search" aria-label="Search"/>}
      />

      <div className={styles.header}>
        <PageHeader
          label="Net worth · all accounts"
          value={<Money value={total} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>}
          sublabel={<span className={styles.posSub}>+ <Money value={812} currency={th.currency}/> this month</span>}
        />
      </div>

      <div className={styles.body}>
        <FinchAccordion type="multiple" defaultValue={DEFAULT_OPEN_GROUPS}>
          {groupedAccounts.map((g) => {
            const groupTotal = g.accounts.reduce((s: number, a: typeof MOCK.accounts[0]) => s + a.balance, 0);
            const empty = g.accounts.length === 0;

            return (
              <FinchAccordionItem key={g.id} value={g.id}>
                <FinchAccordionTrigger>
                  <div className={styles.triggerRow}>
                    <div className={styles.groupName}>{g.name}</div>
                    <span className={styles.groupMeta} style={{ color: empty ? 'var(--muted)' : 'var(--ink2)' }}>
                      {empty ? '—' : `${g.accounts.length} · ${groupTotal < 0 ? '−' : ''}${fmtMoneyShort(groupTotal, th.currency)}`}
                    </span>
                  </div>
                </FinchAccordionTrigger>
                <FinchAccordionContent>
                  {empty ? (
                    <button type="button" className={styles.addBtn}>
                      <Icon name="plus" size={14}/>Add account
                    </button>
                  ) : (
                    <Card padding={0}>
                      {g.accounts.map((a, i) => (
                        <Link key={a.id} href={`/accounts/${a.id}`} className={i ? `${styles.accountRow} ${styles.accountRowDivider}` : styles.accountRow}>
                          <div className={styles.accountBadge} style={{ background: a.color }}>{a.last4.slice(-2)}</div>
                          <div className={styles.accountInfo}>
                            <div className={styles.accountName}>{a.name}</div>
                            <div className={styles.accountLast4}>•••• {a.last4}</div>
                          </div>
                          <div className={styles.accountRight}>
                            <div className={styles.accountBalanceWrap}>
                              <div className={styles.accountBalance} style={{ color: a.balance < 0 ? 'var(--neg)' : 'var(--ink)' }}>
                                {a.balance < 0 ? '−' : ''}{fmtMoneyShort(Math.abs(a.balance), th.currency)}
                              </div>
                            </div>
                            <Icon name="chev" size={12} style={{ color: 'var(--muted)', flexShrink: 0 }}/>
                          </div>
                        </Link>
                      ))}
                    </Card>
                  )}
                </FinchAccordionContent>
              </FinchAccordionItem>
            );
          })}
        </FinchAccordion>
      </div>
    </MobilePage>
  );
}