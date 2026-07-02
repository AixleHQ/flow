// scene-sandbox.jsx — "Watch your agent work" vertical ad (1080x1920, 20s)
// Sandbox isolation story: card gets an agent → dive into live container
// terminal → pull back to reveal parallel isolated sandboxes → PR opened → endcard.
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
const lerp = (a, b, t) => a + (b - a) * t;

function Check({ size = 20, color = C.black, stroke = 3 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round">
      <path d="M20 6L9 17l-5-5" />
    </svg>
  );
}
function BoxIcon({ size = 26, color = C.orange }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 8l-9-5-9 5v8l9 5 9-5V8z" /><path d="M3 8l9 5 9-5M12 13v8" />
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

// ── main terminal log content (local time driven) ──
function MainTermLog({ t }) {
  return (
    <div style={{ padding: '18px 26px 8px' }}>
      <TLine t={t} at={0.0} prefix="▸ " text="docker run --rm aixle/agent:claude-code" color={C.fg2} />
      <TLine t={t} at={1.0} prefix="  " text="container a41f up · 412 ms · network isolated" dim />
      <TLine t={t} at={1.9} text="claude-code --task CPL-217 'Fix flaky auth spec'" />
      <TLine t={t} at={3.1} prefix="  " text="reading test/auth/token_refresh_test.rb …" dim />
      <TLine t={t} at={4.1} prefix="  " text="editing app/services/token_refresher.rb" dim />
      <TLine t={t} at={5.2} text="bin/rails test test/auth" />
      <TLine t={t} at={6.4} prefix="  " text="42 runs, 42 assertions, 0 failures" />
      <TLine t={t} at={7.4} text='git commit -m "stabilize token refresh"' showCursor />
    </div>
  );
}

// mini sandbox card for the parallel strip
function MiniSandbox({ id, task, lines, t, at, x, y, w }) {
  const e = clamp((t - at) / 0.45, 0, 1);
  if (e <= 0) return null;
  const ee = Easing.easeOutBack(e);
  return (
    <div style={{
      position: 'absolute', left: x, top: y, width: w,
      opacity: e, transform: `translateY(${(1 - ee) * 26}px)`,
      background: C.elevated, border: `1px solid ${C.border}`, borderRadius: 18, overflow: 'hidden',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '12px 18px', borderBottom: `1px solid ${C.border}` }}>
        <BoxIcon size={22} />
        <span style={{ fontFamily: FMONO, fontSize: 16, color: C.orangeHi }}>docker:{id}</span>
        <span style={{ fontFamily: FTEXT, fontSize: 17, color: C.fg2, marginLeft: 'auto', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: '55%' }}>{task}</span>
      </div>
      <div style={{ padding: '10px 18px', background: C.termBg }}>
        {lines.map((ln, i) => (
          <TLine key={i} t={t} at={at + 0.5 + i * 0.9} prefix="" text={ln} speed={38}
            color={i === lines.length - 1 ? C.green : undefined} dim={i < lines.length - 1} />
        ))}
      </div>
    </div>
  );
}

function SandboxScene() {
  const { localTime: t } = useSprite();

  // phases: 0-2.6 card view · 2.6-10 terminal dive · 10-15 parallel strip · 15-18 PR done
  const scale = interpolate([0, 0.6, 2.6, 3.4, 10.0, 10.8, 15.0, 15.6, 18], [1.15, 1.2, 1.2, 1.06, 1.06, 0.86, 0.86, 0.98, 0.98], ease)(t);
  const fy = interpolate([0, 2.6, 3.4, 10.0, 10.8, 15.0, 15.6, 18], [560, 560, 780, 780, 1000, 1000, 640, 640], ease)(t);
  const fx = 540;

  const agentAssigned = t >= 1.2;
  const termEnter = clamp((t - 2.2) / 0.5, 0, 1);
  const prDone = t >= 15.4;

  return (
    <World scale={scale} fx={fx} fy={fy}>
      {/* header */}
      <div style={{ position: 'absolute', left: 64, top: 190, fontFamily: FDISP, fontSize: 13, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase' }}>Implementation</div>
      <div style={{ position: 'absolute', left: 62, top: 218, fontFamily: FDISP, fontSize: 54, fontWeight: 400, letterSpacing: '-0.02em', color: C.white, whiteSpace: 'nowrap' }}>Fix flaky auth spec</div>
      <div style={{ position: 'absolute', left: 64, top: 302, fontFamily: FMONO, fontSize: 20, color: C.fg3 }}>CPL-217</div>

      {/* agent chip */}
      <div style={{
        position: 'absolute', right: 64, top: 222, display: 'flex', alignItems: 'center', gap: 12,
        background: agentAssigned ? C.orangeSoft : C.elevated,
        border: `1.5px solid ${agentAssigned ? C.orange : C.border}`,
        borderRadius: 100, padding: '14px 26px',
      }}>
        {!prDone && agentAssigned && (
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={C.orange} strokeWidth="2.4" strokeLinecap="round"><path d="M12 3a9 9 0 1 0 9 9"><animateTransform attributeName="transform" type="rotate" from="0 12 12" to="360 12 12" dur="0.9s" repeatCount="indefinite" /></path></svg>
        )}
        {prDone && <div style={{ width: 24, height: 24, borderRadius: '50%', background: C.green, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Check size={15} /></div>}
        <span style={{ fontFamily: FMONO, fontSize: 20, color: agentAssigned ? C.orangeHi : C.fg2 }}>
          {prDone ? 'PR #342 opened' : agentAssigned ? 'claude-code · docker:a41f' : 'assigning agent…'}
        </span>
      </div>

      {/* main terminal */}
      {termEnter > 0 && (
        <div style={{
          position: 'absolute', left: 64, top: 380, width: 952, height: 560,
          opacity: termEnter, transform: `translateY(${(1 - Easing.easeOutCubic(termEnter)) * 30}px)`,
          background: C.termBg, border: `1.5px solid ${C.borderStrong}`, borderRadius: 22, overflow: 'hidden',
          boxShadow: '0 24px 60px rgba(0,0,0,0.55)',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '14px 22px', background: C.surface, borderBottom: `1px solid ${C.border}` }}>
            <div style={{ display: 'flex', gap: 7 }}>
              <div style={{ width: 12, height: 12, borderRadius: '50%', background: C.orange }} />
              <div style={{ width: 12, height: 12, borderRadius: '50%', background: '#3a3733' }} />
              <div style={{ width: 12, height: 12, borderRadius: '50%', background: '#3a3733' }} />
            </div>
            <span style={{ fontFamily: FMONO, fontSize: 17, color: C.fg2, marginLeft: 8 }}>live session · docker:a41f</span>
            <span style={{ fontFamily: FMONO, fontSize: 14, color: C.orangeHi, marginLeft: 'auto', border: `1px solid rgba(224,88,46,0.4)`, borderRadius: 6, padding: '3px 10px', letterSpacing: '0.06em' }}>SANDBOXED</span>
          </div>
          <MainTermLog t={Math.max(0, t - 3.0)} />
        </div>
      )}

      {/* parallel sandboxes strip */}
      <div style={{ position: 'absolute', left: 64, top: 1010, opacity: clamp((t - 10.2) / 0.4, 0, 1), fontFamily: FDISP, fontSize: 13, fontWeight: 700, letterSpacing: '0.1em', color: C.fg3, textTransform: 'uppercase' }}>
        Also running now — each in its own container
      </div>
      <MiniSandbox id="b7c2" task="Billing usage export" t={t} at={10.6} x={64} y={1060} w={952}
        lines={['codex --task CPL-198', 'writing app/exports/usage_csv.rb …', 'spec green · 18 examples']} />
      <MiniSandbox id="c913" task="Webhook retries" t={t} at={11.2} x={64} y={1268} w={952}
        lines={['claude-code --task CPL-209', 'adding exponential backoff …', 'retries: 5 · jitter on']} />
      <MiniSandbox id="d5e8" task="SSO settings page" t={t} at={11.8} x={64} y={1476} w={952}
        lines={['gemini --task CPL-190', 'scaffolding settings view …', 'tsc --noEmit · 0 errors']} />

      {/* isolation callout */}
      {(() => {
        const e = clamp((t - 13.0) / 0.5, 0, 1);
        if (e <= 0) return null;
        return (
          <div style={{ position: 'absolute', left: 64, top: 1690, width: 952, opacity: e, display: 'flex', alignItems: 'center', gap: 14 }}>
            <BoxIcon size={30} />
            <span style={{ fontFamily: FTEXT, fontSize: 26, fontWeight: 300, color: C.fg2 }}>
              No shared process. No shared files. <span style={{ color: C.white, fontWeight: 500 }}>Full isolation by default.</span>
            </span>
          </div>
        );
      })()}
    </World>
  );
}

function EndCard() {
  const { localTime: t } = useSprite();
  const ringScale = interpolate([0, 2], [1.0, 1.16], Easing.easeOutQuad)(t);
  const ringRot = t * 6;
  const logoE = clamp((t - 0.3) / 0.6, 0, 1);
  const tagE = clamp((t - 0.7) / 0.6, 0, 1);
  return (
    <div style={{ position: 'absolute', inset: 0, background: C.black, overflow: 'hidden' }}>
      <img src="assets/Ring_Orange.png" alt="" style={{ position: 'absolute', left: '50%', top: 470, width: 1180, height: 1180, transform: `translate(-50%,-50%) scale(${ringScale}) rotate(${ringRot}deg)`, opacity: 0.9, objectFit: 'contain' }} />
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(circle at 50% 24%, transparent 30%, rgba(10,9,8,0.55) 60%, #0A0908 82%)' }} />
      <div style={{ position: 'absolute', left: 0, right: 0, top: 1120, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 40 }}>
        <img src="assets/logo-wordmark-white.svg" alt="Aixle" style={{ width: 420, opacity: logoE, transform: `translateY(${(1 - Easing.easeOutCubic(logoE)) * 22}px)` }} />
        <div style={{ fontFamily: FDISP, fontWeight: 700, fontSize: 32, letterSpacing: '0.42em', color: C.orange, marginTop: -18, marginLeft: '0.42em', opacity: logoE }}>FLOW</div>
        <div style={{ maxWidth: 820, textAlign: 'center', fontFamily: FDISP, fontSize: 42, fontWeight: 400, letterSpacing: '-0.02em', color: C.white, lineHeight: 1.12, opacity: tagE, transform: `translateY(${(1 - Easing.easeOutCubic(tagE)) * 18}px)` }}>
          Every agent in its own sandbox. Watch it live.
        </div>
        <div style={{ fontFamily: FMONO, fontSize: 22, color: C.fg2, opacity: tagE, letterSpacing: '0.02em' }}>aixle.com</div>
      </div>
    </div>
  );
}

function SandboxAd() {
  const t = useTime();
  return (
    <div style={{ position: 'absolute', inset: 0, background: C.black }}>
      <Sprite start={0} end={18}><SandboxScene /></Sprite>
      <Sprite start={0} end={18}><Chrome title="CPL-217 · Aixle Flow" url="flow.aixle.com/sessions/a41f" /></Sprite>
      <Sprite start={18} end={20}><EndCard /></Sprite>
    </div>
  );
}
window.SandboxAd = SandboxAd;

function Movie() {
  const { Stage } = window;
  return React.createElement(Stage, { width: 1080, height: 1920, duration: 20, background: C.black, persistKey: 'aixle-sandbox' },
    React.createElement(SandboxAd));
}
window.Movie = Movie;
