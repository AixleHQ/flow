// scene-sandbox-wide.jsx — "Watch your agent work" 16:9 (1920x1080, 20s)
// Wide re-layout: terminal left, parallel sandboxes right column, callout bottom.
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
const VW = 1920, VH = 1080;
const ease = Easing.easeInOutCubic;

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
    <div style={{ position: 'absolute', left: 0, top: 0, width: VW, height: 96, zIndex: 20 }}>
      <div style={{ position: 'absolute', top: 0, left: 0, width: VW, height: 48, background: '#000', display: 'flex', alignItems: 'flex-end', paddingLeft: 24 }}>
        <div style={{ display: 'flex', gap: 8, position: 'absolute', top: 18, left: 24 }}>
          {[0, 1, 2].map((i) => <div key={i} style={{ width: 12, height: 12, borderRadius: '50%', background: '#3f3d3b' }} />)}
        </div>
        <div style={{ marginLeft: 104, height: 36, background: C.surface, borderRadius: '9px 9px 0 0', display: 'flex', alignItems: 'center', gap: 9, padding: '0 16px', maxWidth: 400 }}>
          <div style={{ width: 14, height: 14, borderRadius: 4, background: C.orange, flexShrink: 0 }} />
          <span style={{ fontFamily: FDISP, fontSize: 15, color: C.white, whiteSpace: 'nowrap' }}>{title}</span>
        </div>
      </div>
      <div style={{ position: 'absolute', top: 48, left: 0, width: VW, height: 48, background: C.surface, borderBottom: `1px solid ${C.border}`, display: 'flex', alignItems: 'center', gap: 16, padding: '0 26px' }}>
        <div style={{ display: 'flex', gap: 18, color: C.fg3 }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M15 5l-7 7 7 7" /></svg>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 5l7 7-7 7" /></svg>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7M3 4v4h4" /></svg>
        </div>
        <div style={{ width: 640, height: 32, background: C.black, border: `1px solid ${C.border}`, borderRadius: 16, display: 'flex', alignItems: 'center', gap: 9, padding: '0 16px' }}>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke={C.fg3} strokeWidth="2"><rect x="4" y="9" width="16" height="12" rx="2" /><path d="M8 9V6a4 4 0 0 1 8 0v3" /></svg>
          <span style={{ fontFamily: FMONO, fontSize: 14, color: C.fg2 }}>{url}</span>
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

function TLine({ t, at, speed = 46, prefix = '$ ', text, color = C.green, dim = false, showCursor = false, size = 19 }) {
  if (t < at) return null;
  const chars = Math.floor((t - at) * speed);
  const shown = text.slice(0, chars);
  const done = chars >= text.length;
  return (
    <div style={{ fontFamily: FMONO, fontSize: size, lineHeight: 1.8, color: dim ? C.greenDim : color, whiteSpace: 'pre' }}>
      {prefix}{shown}
      {(!done || showCursor) && <span style={{ display: 'inline-block', width: 10, height: 20, background: C.green, verticalAlign: -3, marginLeft: 2 }} />}
    </div>
  );
}

function MainTermLog({ t }) {
  return (
    <div style={{ padding: '16px 24px 8px' }}>
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

function MiniSandbox({ id, task, lines, t, at, x, y, w }) {
  const e = clamp((t - at) / 0.45, 0, 1);
  if (e <= 0) return null;
  const ee = Easing.easeOutBack(e);
  return (
    <div style={{
      position: 'absolute', left: x, top: y, width: w,
      opacity: e, transform: `translateX(${(1 - ee) * 30}px)`,
      background: C.elevated, border: `1px solid ${C.border}`, borderRadius: 16, overflow: 'hidden',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '10px 16px', borderBottom: `1px solid ${C.border}` }}>
        <BoxIcon size={19} />
        <span style={{ fontFamily: FMONO, fontSize: 14, color: C.orangeHi }}>docker:{id}</span>
        <span style={{ fontFamily: FTEXT, fontSize: 15, color: C.fg2, marginLeft: 'auto', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: '52%' }}>{task}</span>
      </div>
      <div style={{ padding: '8px 16px', background: C.termBg }}>
        {lines.map((ln, i) => (
          <TLine key={i} t={t} at={at + 0.5 + i * 0.9} prefix="" text={ln} speed={38} size={15}
            color={i === lines.length - 1 ? C.green : undefined} dim={i < lines.length - 1} />
        ))}
      </div>
    </div>
  );
}

function SandboxSceneWide() {
  const { localTime: t } = useSprite();

  const scale = interpolate([0, 0.6, 2.6, 3.4, 10.0, 10.8, 18], [1.1, 1.14, 1.14, 1.04, 1.04, 1.0, 1.0], ease)(t);
  const fx = interpolate([0, 2.6, 3.4, 10.0, 10.8, 18], [860, 860, 700, 700, 960, 960], ease)(t);
  const fy = interpolate([0, 2.6, 3.4, 10.0, 10.8, 18], [420, 420, 560, 560, 540, 540], ease)(t);

  const agentAssigned = t >= 1.2;
  const termEnter = clamp((t - 2.2) / 0.5, 0, 1);
  const prDone = t >= 15.4;

  return (
    <World scale={scale} fx={fx} fy={fy}>
      {/* header */}
      <div style={{ position: 'absolute', left: 64, top: 150, fontFamily: FDISP, fontSize: 12, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase' }}>Implementation</div>
      <div style={{ position: 'absolute', left: 62, top: 174, fontFamily: FDISP, fontSize: 46, fontWeight: 400, letterSpacing: '-0.02em', color: C.white, whiteSpace: 'nowrap' }}>Fix flaky auth spec</div>
      <div style={{ position: 'absolute', left: 64, top: 246, fontFamily: FMONO, fontSize: 17, color: C.fg3 }}>CPL-217</div>

      {/* agent chip */}
      <div style={{
        position: 'absolute', left: 500, top: 178, display: 'flex', alignItems: 'center', gap: 11,
        background: agentAssigned ? C.orangeSoft : C.elevated,
        border: `1.5px solid ${agentAssigned ? C.orange : C.border}`,
        borderRadius: 100, padding: '11px 22px',
      }}>
        {!prDone && agentAssigned && (
          <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke={C.orange} strokeWidth="2.4" strokeLinecap="round"><path d="M12 3a9 9 0 1 0 9 9"><animateTransform attributeName="transform" type="rotate" from="0 12 12" to="360 12 12" dur="0.9s" repeatCount="indefinite" /></path></svg>
        )}
        {prDone && <div style={{ width: 21, height: 21, borderRadius: '50%', background: C.green, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Check size={13} /></div>}
        <span style={{ fontFamily: FMONO, fontSize: 17, color: agentAssigned ? C.orangeHi : C.fg2 }}>
          {prDone ? 'PR #342 opened' : agentAssigned ? 'claude-code · docker:a41f' : 'assigning agent…'}
        </span>
      </div>

      {/* main terminal — left column */}
      {termEnter > 0 && (
        <div style={{
          position: 'absolute', left: 64, top: 300, width: 1060, height: 600,
          opacity: termEnter, transform: `translateY(${(1 - Easing.easeOutCubic(termEnter)) * 26}px)`,
          background: C.termBg, border: `1.5px solid ${C.borderStrong}`, borderRadius: 20, overflow: 'hidden',
          boxShadow: '0 24px 60px rgba(0,0,0,0.55)',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '12px 20px', background: C.surface, borderBottom: `1px solid ${C.border}` }}>
            <div style={{ display: 'flex', gap: 6 }}>
              <div style={{ width: 11, height: 11, borderRadius: '50%', background: C.orange }} />
              <div style={{ width: 11, height: 11, borderRadius: '50%', background: '#3a3733' }} />
              <div style={{ width: 11, height: 11, borderRadius: '50%', background: '#3a3733' }} />
            </div>
            <span style={{ fontFamily: FMONO, fontSize: 15, color: C.fg2, marginLeft: 6 }}>live session · docker:a41f</span>
            <span style={{ fontFamily: FMONO, fontSize: 12, color: C.orangeHi, marginLeft: 'auto', border: `1px solid rgba(224,88,46,0.4)`, borderRadius: 6, padding: '2px 9px', letterSpacing: '0.06em' }}>SANDBOXED</span>
          </div>
          <MainTermLog t={Math.max(0, t - 3.0)} />
        </div>
      )}

      {/* right column — parallel sandboxes */}
      <div style={{ position: 'absolute', left: 1180, top: 300, opacity: clamp((t - 10.2) / 0.4, 0, 1), fontFamily: FDISP, fontSize: 12, fontWeight: 700, letterSpacing: '0.1em', color: C.fg3, textTransform: 'uppercase', width: 676 }}>
        Also running now — each in its own container
      </div>
      <MiniSandbox id="b7c2" task="Billing usage export" t={t} at={10.6} x={1180} y={336} w={676}
        lines={['codex --task CPL-198', 'writing app/exports/usage_csv.rb …', 'spec green · 18 examples']} />
      <MiniSandbox id="c913" task="Webhook retries" t={t} at={11.2} x={1180} y={520} w={676}
        lines={['claude-code --task CPL-209', 'adding exponential backoff …', 'retries: 5 · jitter on']} />
      <MiniSandbox id="d5e8" task="SSO settings page" t={t} at={11.8} x={1180} y={704} w={676}
        lines={['gemini --task CPL-190', 'scaffolding settings view …', 'tsc --noEmit · 0 errors']} />

      {/* isolation callout — bottom */}
      {(() => {
        const e = clamp((t - 13.0) / 0.5, 0, 1);
        if (e <= 0) return null;
        return (
          <div style={{ position: 'absolute', left: 64, top: 950, width: 1792, opacity: e, display: 'flex', alignItems: 'center', gap: 13 }}>
            <BoxIcon size={26} />
            <span style={{ fontFamily: FTEXT, fontSize: 24, fontWeight: 300, color: C.fg2 }}>
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
  const ringScale = interpolate([0, 2], [1.0, 1.12], Easing.easeOutQuad)(t);
  const ringRot = t * 6;
  const logoE = clamp((t - 0.3) / 0.6, 0, 1);
  const tagE = clamp((t - 0.7) / 0.6, 0, 1);
  return (
    <div style={{ position: 'absolute', inset: 0, background: C.black, overflow: 'hidden' }}>
      <img src="assets/Ring_Orange.png" alt="" style={{ position: 'absolute', left: '50%', top: 400, width: 860, height: 860, transform: `translate(-50%,-50%) scale(${ringScale}) rotate(${ringRot}deg)`, opacity: 0.9, objectFit: 'contain' }} />
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(circle at 50% 32%, transparent 26%, rgba(10,9,8,0.55) 56%, #0A0908 80%)' }} />
      <div style={{ position: 'absolute', left: 0, right: 0, top: 660, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 26 }}>
        <img src="assets/logo-wordmark-white.svg" alt="Aixle" style={{ width: 340, opacity: logoE, transform: `translateY(${(1 - Easing.easeOutCubic(logoE)) * 20}px)` }} />
        <div style={{ fontFamily: FDISP, fontWeight: 700, fontSize: 26, letterSpacing: '0.42em', color: C.orange, marginTop: -14, marginLeft: '0.42em', opacity: logoE }}>FLOW</div>
        <div style={{ maxWidth: 900, textAlign: 'center', fontFamily: FDISP, fontSize: 36, fontWeight: 400, letterSpacing: '-0.02em', color: C.white, lineHeight: 1.12, opacity: tagE, transform: `translateY(${(1 - Easing.easeOutCubic(tagE)) * 16}px)` }}>
          Every agent in its own sandbox. Watch it live.
        </div>
        <div style={{ fontFamily: FMONO, fontSize: 19, color: C.fg2, opacity: tagE, letterSpacing: '0.02em' }}>aixle.com</div>
      </div>
    </div>
  );
}

function SandboxAdWide() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: C.black }}>
      <Sprite start={0} end={18}><SandboxSceneWide /></Sprite>
      <Sprite start={0} end={18}><Chrome title="CPL-217 · Aixle Flow" url="flow.aixle.com/sessions/a41f" /></Sprite>
      <Sprite start={18} end={20}><EndCard /></Sprite>
    </div>
  );
}
window.SandboxAdWide = SandboxAdWide;

function Movie() {
  const { Stage } = window;
  return React.createElement(Stage, { width: 1920, height: 1080, duration: 20, background: C.black, persistKey: 'aixle-sandbox-wide' },
    React.createElement(SandboxAdWide));
}
window.Movie = Movie;
