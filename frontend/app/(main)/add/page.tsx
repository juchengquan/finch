'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import styles from './add.module.css';

export default function AddExpensePage() {
  const { theme: th } = useTweaks();

  return (
    <MobilePage
      header={
        <ScreenHeader
          back
          title="Add expense"
        />
      }
    >
      <div className={styles.body}>
        <div className={styles.amountSection}>
          <div className={styles.amountLabel}>AMOUNT</div>
          <div className={styles.amountRow}>
            <span className={styles.amountSign}>$</span>
            <span className={styles.amountWhole}>42</span>
            <span className={styles.amountCents}>.18</span>
          </div>
        </div>

        <div>
          <div className={styles.field}>
            <div className={styles.fieldIcon}><Icon name="tag" size={15}/></div>
            <div className={styles.fieldBody}>
              <div className={styles.fieldLabel}>Merchant</div>
              <div className={styles.fieldValue}>Auto-detected</div>
            </div>
          </div>
          <div className={styles.field}>
            <div className={styles.fieldIcon}><Icon name="fork" size={15}/></div>
            <div className={styles.fieldBody}>
              <div className={styles.fieldLabel}>Category</div>
              <div className={styles.fieldValue}>Food & Dining</div>
            </div>
            <Icon name="chev" size={14} style={{ color: th.muted }}/>
          </div>
          <div className={styles.field}>
            <div className={styles.fieldIcon}><Icon name="wallet" size={15}/></div>
            <div className={styles.fieldBody}>
              <div className={styles.fieldLabel}>Account</div>
              <div className={styles.fieldValue}>Amex Gold · 1009</div>
            </div>
            <Icon name="chev" size={14} style={{ color: th.muted }}/>
          </div>
          <div className={styles.field}>
            <div className={styles.fieldIcon}><Icon name="calendar" size={15}/></div>
            <div className={styles.fieldBody}>
              <div className={styles.fieldLabel}>Date</div>
              <div className={styles.fieldValue}>Today</div>
            </div>
            <Icon name="chev" size={14} style={{ color: th.muted }}/>
          </div>
        </div>

        <button type="submit" className={styles.submitBtn}>
          Save expense
        </button>
      </div>
    </MobilePage>
  );
}