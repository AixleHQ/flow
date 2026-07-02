// scene-bill.jsx — "The Bill" vertical ad (1080x1920, 15s)
// Transparent costs story: usage dashboard → spend counts up → daily bars →
// per-runtime breakdown → session receipt → endcard.
const { Sprite, useSprite, useTime, Easing, interpolate, clamp } = window;

const C = {
  black: '#0A0908', surface: '#191817', elevated: '#1C1A18',
  border: '#292726', borderStrong: '#393837',
  white: '#D1CFCD', fg2: '#9F9D9C', fg3: '#7F7E7C',
  orange: '#E0582E', orangeHi: '#EC6A41', orangeSoft: 'rgba(224,88,46,0.14)',
  green: '#4BC46F', greenDim: '#3a6b48', termBg: '#0C0C0B',
};
const FDISP = "'Hanken Grotesk','Helvetica Neue',Helvetica,Arial,sans-serif";
const FTEXT = "'Figtree','Helvetica Neue',Helvetica,Arial,sans-serif";
const FMONO = "'Spline Sans Mono',ui-monospace,monospace";
const VW = 1080, VH = 1920;
const ease = Easing.easeInOutCubic;

function Check({ size = 20, color = C.black, stroke = 3 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round">
      <path d="M20 6L9 17l-5-5" />
    </svg>
  );
}

function Chrome({ title, url }) {
  return (
    <div style={{ position: 'absolute', left: 0, top: 0, width: VW, height: 122, zIndex: 20 }}>
      <div style={{ position: 'absolute', top: 0, left: 0, width: VW, height: 60, background: '#000', display: 'flex', alignItems: 'flex-end', paddingLeft: 26 }}>
        <div style={{ display: 'flex', gap: 9, position: 'absolute', top: 22, left: 26 }}>
          {[0, 1, 2].map((i) => <div key={i} style={{ width: 13, height: 13, borderRadius: '50%', background: '#3f3d3b' }} />)}
        </div>
        <div style={{ marginLeft: 118, height: 44, background: C.surface, borderRadius: '10px 10px 0 0', display: 'flex', alignItems: 'center', gap: 10, padding: '0 18px', maxWidth: 460 }}>
          <div style={{ width: 16, height: 16, borderRadius: 4, background: C.orange, flexShrink: 0 }} />
          <span style={{ fontFamily: FDISP, fontSize: 18, color: C.white, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</span>
        </div>
      </div>
      <div style={{ position: 'absolute', top: 60, left: 0, width: VW, height: 62, background: C.surface, borderBottom: `1px solid ${C.border}`, display: 'flex', alignItems: 'center', gap: 18, padding: '0 30px' }}>
        <div style={{ display: 'flex', gap: 22, color: C.fg3 }}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M15 5l-7 7 7 7" /></svg>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 5l7 7-7 7" /></svg>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7M3 4v4h4" /></svg>
        </div>
        <div style={{ flex: 1, height: 40, background: C.black, border: `1px solid ${C.border}`, borderRadius: 20, display: 'flex', alignItems: 'center', gap: 10, padding: '0 18px' }}>
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={C.fg3} strokeWidth="2"><rect x="4" y="9" width="16" height="12" rx="2" /><path d="M8 9V6a4 4 0 0 1 8 0v3" /></svg>
          <span style={{ fontFamily: FMONO, fontSize: 16, color: C.fg2 }}>{url}</span>
        </div>
      </div>
    </div>
  );
}

function World({ scale, fx, fy, children }) {
  const tx = VW / 2 - fx * scale;
  const ty = VH / 2 - fy * scale;
  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', background: C.black }}>
      <div style={{ position: 'absolute', width: VW, height: VH, transformOrigin: '0 0', transform: `translate(${tx}px,${ty}px) scale(${scale})`, willChange: 'transform' }}>
        {children}
      </div>
    </div>
  );
}

// typed terminal line: reveals characters over time
function TLine({ t, at, speed = 46, prefix = '$ ', text, color = C.green, dim = false, showCursor = false }) {
  if (t < at) return null;
  const chars = Math.floor((t - at) * speed);
  const shown = text.slice(0, chars);
  const done = chars >= text.length;
  return (
    <div style={{ fontFamily: FMONO, fontSize: 21, lineHeight: 1.8, color: dim ? C.greenDim : color, whiteSpace: 'pre' }}>
      {prefix}{shown}
      {(!done || showCursor) && <span style={{ display: 'inline-block', width: 11, height: 22, background: C.green, verticalAlign: -3, marginLeft: 2 }} />}
    </div>
  );
}

// stat tile with big mono number
function StatTile({ t, at, x, y, w, h, value, label, accent = false }) {
  const e = clamp((t - at) / 0.45, 0, 1);
  const ee = Easing.easeOutBack(e);
  return (
    <div style={{
      position: 'absolute', left: x, top: y, width: w, height: h,
      opacity: e, transform: `translateY(${(1 - ee) * 26}px)`,
      background: C.elevated, border: `1px solid ${C.border}`, borderRadius: 18, padding: '26px 24px', overflow: 'hidden',
    }}>
      <div style={{ fontFamily: FMONO, fontSize: 50, letterSpacing: '-0.01em', color: accent ? C.orangeHi : C.white, whiteSpace: 'nowrap', fontVariantNumeric: 'tabular-nums' }}>{value}</div>
      <div style={{ marginTop: 12, fontFamily: FTEXT, fontSize: 18, color: C.fg3, whiteSpace: 'nowrap' }}>{label}</div>
    </div>
  );
}

const DAYS = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const PCTS = [34, 52, 41, 78, 64, 22, 12];
const PEAK = 3; // THU

const RUNTIMES = [
  { name: 'Claude Code', amount: '$29.40', frac: 1.0, dot: C.orange },
  { name: 'Codex', amount: '$11.15', frac: 11.15 / 29.4, dot: C.green },
  { name: 'Gemini CLI', amount: '$5.30', frac: 5.3 / 29.4, dot: '#5E9ED6' },
  { name: 'Cursor CLI', amount: '$2.35', frac: 2.35 / 29.4, dot: C.fg2 },
];

function BillScene() {
  const { localTime: t } = useSprite();

  // phases: 0-2 header+tiles · 2-8 daily bars · 6-10 runtime rows · 10-13 receipt
  const scale = interpolate([0, 0.6, 2.4, 3.2, 5.8, 6.6, 9.8, 10.6, 13], [1.06, 1.1, 1.1, 1.02, 1.02, 0.94, 0.94, 0.9, 0.9], ease)(t);
  const fy = interpolate([0, 2.4, 3.2, 5.8, 6.6, 9.8, 10.6, 13], [560, 560, 820, 820, 1020, 1020, 1150, 1150], ease)(t);
  const fx = 540;

  const headE = clamp((t - 0.05) / 0.5, 0, 1);
  const chartE = clamp((t - 2.0) / 0.5, 0, 1);
  const runtimeE = clamp((t - 6.0) / 0.5, 0, 1);
  const receiptE = clamp((t - 10.2) / 0.6, 0, 1);

  const spend = interpolate([0.3, 6.0], [0, 48.20], Easing.easeOutCubic)(Math.min(t, 6.0));
  const tokens = interpolate([0.55, 3.2], [0, 1.84], Easing.easeOutCubic)(Math.min(t, 3.2));
  const sessions = interpolate([0.8, 3.4], [0, 312], Easing.easeOutCubic)(Math.min(t, 3.4));

  return (
    <World scale={scale} fx={fx} fy={fy}>
      {/* header */}
      <div style={{ position: 'absolute', inset: 0, opacity: headE, transform: `translateY(${(1 - Easing.easeOutCubic(headE)) * 20}px)` }}>
        <div style={{ position: 'absolute', left: 64, top: 190, fontFamily: FDISP, fontSize: 13, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase' }}>Usage — copperline</div>
        <div style={{ position: 'absolute', left: 62, top: 218, fontFamily: FDISP, fontSize: 54, fontWeight: 400, letterSpacing: '-0.02em', color: C.white, whiteSpace: 'nowrap' }}>Agent spend — July</div>
        <div style={{ position: 'absolute', left: 64, top: 302, fontFamily: FMONO, fontSize: 20, color: C.fg3, whiteSpace: 'nowrap' }}>Jul 1 – Jul 31 · all runtimes</div>
      </div>

      {/* stat tiles */}
      <StatTile t={t} at={0.3} x={64} y={350} w={304} h={172} value={`$ ${spend.toFixed(2)}`} label="spend this month" accent />
      <StatTile t={t} at={0.55} x={388} y={350} w={304} h={172} value={`${tokens.toFixed(2)} M`} label="tokens" />
      <StatTile t={t} at={0.8} x={712} y={350} w={304} h={172} value={`${Math.round(sessions)}`} label="sessions" />

      {/* daily spend bar chart */}
      <div style={{
        position: 'absolute', left: 64, top: 562, width: 952, height: 392,
        opacity: chartE, transform: `translateY(${(1 - Easing.easeOutCubic(chartE)) * 30}px)`,
        background: C.elevated, border: `1px solid ${C.border}`, borderRadius: 18, padding: '24px 26px', overflow: 'hidden',
      }}>
        <div style={{ display: 'flex', alignItems: 'baseline', height: 30 }}>
          <span style={{ fontFamily: FDISP, fontSize: 24, fontWeight: 400, letterSpacing: '-0.01em', color: C.white, whiteSpace: 'nowrap' }}>Daily spend</span>
          <span style={{ marginLeft: 'auto', fontFamily: FMONO, fontSize: 16, color: C.fg3, whiteSpace: 'nowrap' }}>avg $6.89 / day</span>
        </div>
        <div style={{ marginTop: 18, display: 'flex', justifyContent: 'space-between', borderBottom: `1px solid ${C.border}` }}>
          {PCTS.map((pct, i) => {
            const at = 2.6 + i * 0.5;
            const e = Easing.easeOutCubic(clamp((t - at) / 0.7, 0, 1));
            const barH = (pct / 100) * 260 * e;
            const peakE = clamp((t - 4.9) / 0.4, 0, 1);
            return (
              <div key={i} style={{ width: 84, height: 260, position: 'relative' }}>
                <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: barH, background: i === PEAK ? C.orange : 'rgba(224,88,46,0.45)', borderRadius: '6px 6px 0 0' }} />
                {i === PEAK && (
                  <span style={{ position: 'absolute', left: '50%', bottom: 214, transform: 'translateX(-50%)', opacity: peakE, fontFamily: FMONO, fontSize: 16, color: C.orangeHi, whiteSpace: 'nowrap', fontVariantNumeric: 'tabular-nums' }}>$12.40</span>
                )}
              </div>
            );
          })}
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 12 }}>
          {DAYS.map((d) => (
            <span key={d} style={{ width: 84, textAlign: 'center', fontFamily: FMONO, fontSize: 15, letterSpacing: '0.04em', color: C.fg3, whiteSpace: 'nowrap' }}>{d}</span>
          ))}
        </div>
      </div>

      {/* by runtime */}
      <div style={{
        position: 'absolute', left: 64, top: 994, width: 952, height: 368,
        opacity: runtimeE, transform: `translateY(${(1 - Easing.easeOutCubic(runtimeE)) * 30}px)`,
        background: C.elevated, border: `1px solid ${C.border}`, borderRadius: 18, padding: '24px 24px', overflow: 'hidden',
      }}>
        <div style={{ display: 'flex', alignItems: 'baseline', height: 30 }}>
          <span style={{ fontFamily: FDISP, fontSize: 24, fontWeight: 400, letterSpacing: '-0.01em', color: C.white, whiteSpace: 'nowrap' }}>By runtime</span>
          <span style={{ marginLeft: 'auto', fontFamily: FMONO, fontSize: 16, color: C.fg3, whiteSpace: 'nowrap' }}>share of spend</span>
        </div>
        <div style={{ marginTop: 18 }}>
          {RUNTIMES.map((r, i) => {
            const at = 6.4 + i * 0.6;
            const e = clamp((t - at) / 0.5, 0, 1);
            const ee = Easing.easeOutBack(e);
            const uw = Easing.easeOutCubic(clamp((t - at - 0.3) / 0.8, 0, 1)) * r.frac * 904;
            return (
              <div key={r.name} style={{ height: 56, marginBottom: i < RUNTIMES.length - 1 ? 16 : 0, opacity: e, transform: `translateY(${(1 - ee) * 22}px)` }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                  <div style={{ width: 12, height: 12, borderRadius: '50%', background: r.dot, flexShrink: 0 }} />
                  <span style={{ fontFamily: FTEXT, fontSize: 22, color: C.white, whiteSpace: 'nowrap' }}>{r.name}</span>
                  <span style={{ marginLeft: 'auto', fontFamily: FMONO, fontSize: 22, color: C.white, whiteSpace: 'nowrap', fontVariantNumeric: 'tabular-nums' }}>{r.amount}</span>
                </div>
                <div style={{ marginTop: 12, height: 3, borderRadius: 2, background: 'rgba(255,255,255,0.06)', position: 'relative', overflow: 'hidden' }}>
                  <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: uw, background: C.orange, borderRadius: 2 }} />
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* session receipt */}
      <div style={{
        position: 'absolute', left: 64, top: 1414, width: 952, height: 224,
        opacity: receiptE, transform: `translateY(${(1 - Easing.easeOutCubic(receiptE)) * 80}px)`,
        background: C.termBg, border: `1.5px solid ${C.borderStrong}`, borderRadius: 22, padding: '22px 26px', overflow: 'hidden',
        boxShadow: '0 24px 60px rgba(0,0,0,0.55)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', height: 36 }}>
          <span style={{ fontFamily: FDISP, fontSize: 13, fontWeight: 700, letterSpacing: '0.1em', color: C.fg3, textTransform: 'uppercase' }}>Session receipt</span>
          {(() => {
            const e = clamp((t - 12.2) / 0.45, 0, 1);
            const ee = Easing.easeOutBack(e);
            return (
              <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 10, opacity: e, transform: `scale(${0.7 + 0.3 * ee})`, border: '1px solid rgba(75,196,111,0.45)', borderRadius: 100, padding: '7px 16px' }}>
                <div style={{ width: 20, height: 20, borderRadius: '50%', background: C.green, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Check size={13} /></div>
                <span style={{ fontFamily: FMONO, fontSize: 17, color: C.green }}>audited</span>
              </div>
            );
          })()}
        </div>
        <div style={{ marginTop: 10 }}>
          <TLine t={t} at={10.7} prefix="" text="session a41f · CPL-217" color={C.white} speed={40} />
          <TLine t={t} at={11.3} prefix="" text="tokens 12,408 · $0.19" color={C.fg2} speed={40} />
          <TLine t={t} at={11.9} prefix="" text="prompt + transcript stored" speed={40} showCursor />
        </div>
      </div>
    </World>
  );
}

function EndCard() {
  const { localTime: t } = useSprite();
  const ringScale = interpolate([0, 2], [1.0, 1.16], Easing.easeOutQuad)(t);
  const ringRot = t * 6;
  const logoE = clamp((t - 0.3) / 0.6, 0, 1);
  const tagE = clamp((t - 0.7) / 0.6, 0, 1);
  const subE = clamp((t - 0.95) / 0.6, 0, 1);
  return (
    <div style={{ position: 'absolute', inset: 0, background: C.black, overflow: 'hidden' }}>
      <img src="assets/Ring_Orange.png" alt="" style={{ position: 'absolute', left: '50%', top: 470, width: 1180, height: 1180, transform: `translate(-50%,-50%) scale(${ringScale}) rotate(${ringRot}deg)`, opacity: 0.9, objectFit: 'contain' }} />
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(circle at 50% 24%, transparent 30%, rgba(10,9,8,0.55) 60%, #0A0908 82%)' }} />
      <div style={{ position: 'absolute', left: 0, right: 0, top: 1120, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 32 }}>
        <img src="assets/logo-wordmark-white.svg" alt="Aixle" style={{ width: 420, opacity: logoE, transform: `translateY(${(1 - Easing.easeOutCubic(logoE)) * 22}px)` }} />
        <div style={{ fontFamily: FDISP, fontWeight: 700, fontSize: 32, letterSpacing: '0.42em', color: C.orange, marginTop: -18, marginLeft: '0.42em', opacity: logoE }}>FLOW</div>
        <div style={{ maxWidth: 820, textAlign: 'center', fontFamily: FDISP, fontSize: 42, fontWeight: 400, letterSpacing: '-0.02em', color: C.white, lineHeight: 1.12, opacity: tagE, transform: `translateY(${(1 - Easing.easeOutCubic(tagE)) * 18}px)` }}>
          Every token accounted.
        </div>
        <div style={{ maxWidth: 820, textAlign: 'center', fontFamily: FTEXT, fontSize: 28, fontWeight: 300, color: C.fg2, opacity: subE, transform: `translateY(${(1 - Easing.easeOutCubic(subE)) * 16}px)` }}>
          Export the invoice.
        </div>
        <div style={{ fontFamily: FMONO, fontSize: 22, color: C.fg2, opacity: subE, letterSpacing: '0.02em' }}>aixle.com</div>
      </div>
    </div>
  );
}

function BillAd() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: C.black }}>
      <Sprite start={0} end={13}><BillScene /></Sprite>
      <Sprite start={0} end={13}><Chrome title="Usage · Aixle Flow" url="flow.aixle.com/copperline/usage" /></Sprite>
      <Sprite start={13} end={15}><EndCard /></Sprite>
    </div>
  );
}
window.BillAd = BillAd;

function Movie() {
  const { Stage } = window;
  return React.createElement(Stage, { width: 1080, height: 1920, duration: 15, background: C.black, persistKey: 'aixle-bill-v' },
    React.createElement(BillAd));
}
window.Movie = Movie;
