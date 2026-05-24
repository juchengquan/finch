// Minimal iPad device frame — landscape, single-orientation.
// Renders a rounded-corner bezel with a thin status bar at top and a home
// indicator at bottom. No camera notch (modern iPad has the front camera in
// the long-edge bezel and Liquid Retina is uniform). The inner display
// hosts whatever children you pass — typically a WebShell for parity with
// the desktop pages.

const IPAD_INNER_W = 1180;
const IPAD_INNER_H = 820;
const IPAD_BEZEL = 28;
const IPAD_STATUS = 28;
const IPAD_INDICATOR = 32;

function IPadStatusBar({ dark = false }) {
  const c = dark ? '#fff' : '#1a1614';
  return (
    <div style={{
      height: IPAD_STATUS, padding: '0 22px',
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      fontFamily: '-apple-system, "SF Pro Text", system-ui', fontSize: 13, fontWeight: 600,
      color: c,
    }}>
      <span style={{ letterSpacing: 0.2 }}>9:41 Sat May 24</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, opacity: 0.95 }}>
        {/* Wi-Fi */}
        <svg width="16" height="11" viewBox="0 0 16 11" fill="none">
          <path d="M8 10.5a1 1 0 1 0 0-2 1 1 0 0 0 0 2zM3 6c1.4-1.4 3.1-2.2 5-2.2S11.6 4.6 13 6l-1 1c-1.1-1.1-2.5-1.7-4-1.7s-2.9.6-4 1.7L3 6zM0 3c2.3-2.3 5-3.5 8-3.5S13.7.7 16 3l-1 1c-2-2-4.4-3-7-3S3 2 1 4L0 3z" fill={c}/>
        </svg>
        {/* Battery */}
        <svg width="26" height="12" viewBox="0 0 26 12">
          <rect x="0.5" y="0.5" width="22" height="11" rx="3" stroke={c} strokeOpacity="0.35" fill="none"/>
          <rect x="2" y="2" width="18" height="8" rx="1.5" fill={c}/>
          <path d="M24 4v4c.8-.3 1.5-1.2 1.5-2s-.7-1.7-1.5-2z" fill={c} fillOpacity="0.4"/>
        </svg>
      </div>
    </div>
  );
}

function IPadDevice({ children, width = IPAD_INNER_W + IPAD_BEZEL * 2, height = IPAD_INNER_H + IPAD_BEZEL * 2 + IPAD_INDICATOR, dark = false }) {
  return (
    <div style={{
      width, height, borderRadius: 38, overflow: 'hidden',
      background: dark ? '#0a0a0a' : '#1c1a17',
      padding: IPAD_BEZEL, paddingBottom: IPAD_BEZEL + IPAD_INDICATOR / 2,
      boxShadow: '0 32px 80px rgba(0,0,0,0.22), 0 0 0 1px rgba(0,0,0,0.15)',
      boxSizing: 'border-box',
      position: 'relative',
      fontFamily: '-apple-system, system-ui, sans-serif',
    }}>
      {/* Screen */}
      <div style={{
        width: width - IPAD_BEZEL * 2, height: height - IPAD_BEZEL * 2 - IPAD_INDICATOR / 2,
        borderRadius: 10, overflow: 'hidden',
        background: dark ? '#000' : '#f5f1ea',
        display: 'flex', flexDirection: 'column',
        position: 'relative',
      }}>
        <IPadStatusBar dark={dark}/>
        <div style={{ flex: 1, overflow: 'hidden' }}>{children}</div>
      </div>
      {/* Home indicator */}
      <div style={{
        position: 'absolute', bottom: 10, left: '50%', transform: 'translateX(-50%)',
        width: 120, height: 4, borderRadius: 2,
        background: 'rgba(255,255,255,0.55)',
      }}/>
    </div>
  );
}

Object.assign(window, { IPadDevice, IPAD_INNER_W, IPAD_INNER_H, IPAD_BEZEL, IPAD_STATUS, IPAD_INDICATOR });
