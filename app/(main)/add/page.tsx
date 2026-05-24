'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';

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
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14, padding: '16px 20px 120px' }}>
        <div style={{ textAlign: 'center', paddingTop: 20 }}>
          <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.5, color: th.muted, marginBottom: 14 }}>AMOUNT</div>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'center', gap: 6 }}>
            <span style={{ fontFamily: th.display, fontSize: 32, color: th.muted, alignSelf: 'flex-start', marginTop: 18 }}>$</span>
            <span style={{ fontFamily: th.display, fontSize: 84, lineHeight: 1, letterSpacing: -3, fontWeight: 400 }}>42</span>
            <span style={{ fontFamily: th.display, fontSize: 40, color: th.muted }}>.18</span>
          </div>
        </div>

        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 20px', borderBottom: `1px solid ${th.line}` }}>
            <div style={{ width: 32, height: 32, borderRadius: 16, background: th.paperAlt, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink2, flexShrink: 0 }}><Icon name="tag" size={15}/></div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 11, color: th.muted, letterSpacing: 0.4, textTransform: 'uppercase' }}>Merchant</div>
              <div style={{ fontSize: 15, marginTop: 1 }}>Auto-detected</div>
            </div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 20px', borderBottom: `1px solid ${th.line}` }}>
            <div style={{ width: 32, height: 32, borderRadius: 16, background: th.paperAlt, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink2, flexShrink: 0 }}><Icon name="fork" size={15}/></div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 11, color: th.muted, letterSpacing: 0.4, textTransform: 'uppercase' }}>Category</div>
              <div style={{ fontSize: 15, marginTop: 1 }}>Food & Dining</div>
            </div>
            <Icon name="chev" size={14} style={{ color: th.muted }}/>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 20px', borderBottom: `1px solid ${th.line}` }}>
            <div style={{ width: 32, height: 32, borderRadius: 16, background: th.paperAlt, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink2, flexShrink: 0 }}><Icon name="wallet" size={15}/></div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 11, color: th.muted, letterSpacing: 0.4, textTransform: 'uppercase' }}>Account</div>
              <div style={{ fontSize: 15, marginTop: 1 }}>Amex Gold · 1009</div>
            </div>
            <Icon name="chev" size={14} style={{ color: th.muted }}/>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 20px', borderBottom: `1px solid ${th.line}` }}>
            <div style={{ width: 32, height: 32, borderRadius: 16, background: th.paperAlt, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink2, flexShrink: 0 }}><Icon name="calendar" size={15}/></div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 11, color: th.muted, letterSpacing: 0.4, textTransform: 'uppercase' }}>Date</div>
              <div style={{ fontSize: 15, marginTop: 1 }}>Today</div>
            </div>
            <Icon name="chev" size={14} style={{ color: th.muted }}/>
          </div>
        </div>

        <button type="submit" style={{ height: 54, borderRadius: 27, background: th.ink, color: th.paper, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 16, fontWeight: 500, letterSpacing: -0.2, cursor: 'pointer', border: 'none', fontFamily: 'inherit', marginTop: 8 }}>
          Save expense
        </button>
      </div>
    </MobilePage>
  );
}