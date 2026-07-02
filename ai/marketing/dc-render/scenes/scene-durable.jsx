// scene-durable.jsx — "Runs that survive" vertical ad (1080x1920, 20s)
// Durable orchestration story: 4-node DAG runs → worker dies mid-stage →
// run resumes from checkpoint (nothing lost) → CI green → human approves → endcard.
const { Sprite, useSprite, useTime, Easing, interpolate, clamp } = window;

const C = {
  black: '#0A0908', surface: '#191817', elevated: '#1C1A18',
  border: '#292726', borderStrong: '#393837',
  white: '#D1CFCD', fg2: '#9F9D9C', fg3: '#7F7E7C',
  orange: '#E0582E', orangeHi: '#EC6A41', orangeSoft: 'rgba(224,88,46,0.14)',
  green: '#4BC46F', greenDim: '#3a6b48', termBg: '#0C0C0B',
};
const AMBER = '#DFA33C';
const RED = '#E5534B';
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

// ── Cursor ────────────────────────────────────────────────────────────────
function Cursor({ x, y, opacity = 1, pressed = false }) {
  return (
    <div style={{
      position: 'absolute', left: x, top: y, opacity,
      transform: `scale(${pressed ? 0.85 : 1})`, transformOrigin: '4px 4px',
      willChange: 'left,top,transform,opacity', zIndex: 50, pointerEvents: 'none',
      filter: 'drop-shadow(0 3px 6px rgba(0,0,0,0.55))',
    }}>
      <svg width="40" height="40" viewBox="0 0 24 24" fill="none">
        <path d="M5 3l14 8-6 1.5L10 20 5 3z" fill="#fff" stroke="#0A0908" strokeWidth="1.4" strokeLinejoin="round" />
      </svg>
    </div>
  );
}
function ClickRing({ x, y, t0, localTime }) {
  const dt = localTime - t0;
  if (dt < 0 || dt > 0.55) return null;
  const p = dt / 0.55;
  return (
    <div style={{
      position: 'absolute', left: x, top: y, zIndex: 49,
      width: 8, height: 8, marginLeft: -4, marginTop: -4,
      borderRadius: '50%', border: `2px solid ${C.orange}`,
      transform: `scale(${1 + p * 7})`, opacity: (1 - p) * 0.9,
    }} />
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

// ── DAG building blocks ─────────────────────────────────────────────────────
function StatusDot({ state, size = 36 }) {
  if (state === 'done') {
    return (
      <div style={{ width: size, height: size, borderRadius: '50%', background: C.green, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <Check size={size * 0.55} />
      </div>
    );
  }
  if (state === 'active') {
    return (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={C.orange} strokeWidth="2.4" strokeLinecap="round">
        <path d="M12 3a9 9 0 1 0 9 9"><animateTransform attributeName="transform" type="rotate" from="0 12 12" to="360 12 12" dur="0.9s" repeatCount="indefinite" /></path>
      </svg>
    );
  }
  return <div style={{ width: size, height: size, borderRadius: '50%', border: `2px solid ${C.borderStrong}` }} />;
}

function NodeCard({ t, at, x, y, w, h, step, title, sub, state, children }) {
  const e = clamp((t - at) / 0.45, 0, 1);
  if (e <= 0) return null;
  const ee = Easing.easeOutBack(e);
  let border = `1.5px solid ${C.border}`;
  if (state === 'active') {
    const p = 0.5 + 0.5 * Math.sin(t * Math.PI * 2 / 1.4);
    border = `1.5px solid rgba(224,88,46,${(0.45 + 0.45 * p).toFixed(3)})`;
  } else if (state === 'done') {
    border = `1.5px solid ${C.borderStrong}`;
  }
  return (
    <div style={{
      position: 'absolute', left: x, top: y, width: w, height: h,
      opacity: e, transform: `translateY(${(1 - ee) * 24}px)`,
      background: C.elevated, border, borderRadius: 20,
    }}>
      <div style={{ position: 'absolute', left: 24, top: 26 }}><StatusDot state={state} /></div>
      <div style={{ position: 'absolute', left: 84, top: 26, fontFamily: FDISP, fontSize: 29, fontWeight: 500, color: C.white, whiteSpace: 'nowrap' }}>{title}</div>
      {sub && <div style={{ position: 'absolute', left: 84, top: 70, fontFamily: FMONO, fontSize: 17, color: C.fg3, whiteSpace: 'nowrap' }}>{sub}</div>}
      <div style={{ position: 'absolute', right: 24, top: 30, fontFamily: FMONO, fontSize: 16, color: C.fg3, whiteSpace: 'nowrap' }}>{step}</div>
      {children}
    </div>
  );
}

function Connector({ t, at, x, y, h }) {
  const f = clamp((t - at) / 0.5, 0, 1);
  return (
    <div style={{ position: 'absolute', left: x, top: y, width: 5, height: h, borderRadius: 3, background: C.border }}>
      <div style={{ position: 'absolute', left: 0, top: 0, width: 5, height: h * Easing.easeOutCubic(f), borderRadius: 3, background: C.orange }} />
    </div>
  );
}

function CiChip({ label, on }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 9, padding: '8px 18px', borderRadius: 100,
      border: `1.5px solid ${on ? 'rgba(75,196,111,0.55)' : C.border}`,
      background: on ? 'rgba(75,196,111,0.10)' : C.surface,
    }}>
      {on ? <Check size={14} color={C.green} stroke={3.5} /> : <div style={{ width: 8, height: 8, borderRadius: '50%', background: C.fg3 }} />}
      <span style={{ fontFamily: FMONO, fontSize: 17, color: on ? C.green : C.fg3 }}>{label}</span>
    </div>
  );
}

function DurableScene() {
  const { localTime: t } = useSprite();

  // phases: 0-3 run starts · 3-4.5 disaster · 4.5-6 resume · 6-10 CI · 10-15 gate · 15-18 summary
  const baseScale = interpolate([0, 0.6, 6.6, 7.4, 10.2, 11.0, 14.6, 15.4, 18], [1.16, 1.2, 1.2, 1.12, 1.12, 1.1, 1.1, 0.94, 0.94], ease)(t);
  const dagPulse = interpolate([13.15, 13.4, 13.7], [1, 1.015, 1], ease)(clamp(t, 13.15, 13.7));
  const scale = baseScale * dagPulse;
  const fy = interpolate([0, 6.6, 7.4, 10.2, 11.0, 14.6, 15.4, 18], [640, 640, 900, 900, 1120, 1120, 940, 940], ease)(t);
  const fx = 540;

  // node states
  const n1 = t < 0.5 ? 'idle' : t < 1.2 ? 'active' : 'done';
  const n2 = t < 1.6 ? 'idle' : t < 6.4 ? 'active' : 'done';
  const n3 = t < 6.9 ? 'idle' : t < 9.8 ? 'active' : 'done';
  const approved = t >= 13.05;
  const n4 = t < 10.3 ? 'idle' : approved ? 'done' : 'active';

  // node 2 progress: to 60%, hold through the crash, then resume from 60% — never from zero
  const prog = interpolate([1.6, 3.0, 4.8, 6.4], [0, 0.6, 0.6, 1], ease)(clamp(t, 1.6, 6.4));
  const resumeE = clamp((t - 4.7) / 0.4, 0, 1);

  // disaster beat: dim overlay + sliding banner
  const dimO = interpolate([3.0, 3.35, 4.15, 4.6], [0, 0.65, 0.65, 0], ease)(clamp(t, 3.0, 4.6));
  const bannerY = interpolate([3.0, 3.45, 4.1, 4.55], [-260, 0, 0, -260], ease)(clamp(t, 3.0, 4.55));
  const bannerOn = t >= 3.0 && t <= 4.55;

  // cursor → Approve
  const curOn = t >= 11.6 && t <= 14.2;
  const curX = interpolate([11.6, 12.9], [1010, 890], ease)(clamp(t, 11.6, 12.9));
  const curY = interpolate([11.6, 12.9], [1560, 1262], ease)(clamp(t, 11.6, 12.9));
  const curOp = clamp((t - 11.6) / 0.4, 0, 1) * (1 - clamp((t - 13.6) / 0.4, 0, 1));
  const pressed = t >= 13.0 && t < 13.12;

  // gate chip pulse (calm)
  const waitPulse = 0.5 + 0.5 * Math.sin(t * Math.PI * 2 / 1.8);

  // run status chip
  let chipLabel = 'run #482 · running';
  if (t >= 3.2 && t < 4.8) chipLabel = 'worker lost · resuming';
  if (approved) chipLabel = 'run #482 · complete';

  const summaryE = clamp((t - 14.8) / 0.5, 0, 1);
  const calloutE = clamp((t - 15.5) / 0.5, 0, 1);

  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      <World scale={scale} fx={fx} fy={fy}>
        {/* header */}
        <div style={{ position: 'absolute', left: 64, top: 190, fontFamily: FDISP, fontSize: 13, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase' }}>Durable orchestration</div>
        <div style={{ position: 'absolute', left: 62, top: 218, fontFamily: FDISP, fontSize: 54, fontWeight: 400, letterSpacing: '-0.02em', color: C.white, whiteSpace: 'nowrap' }}>Runs that survive</div>
        <div style={{ position: 'absolute', left: 64, top: 302, fontFamily: FMONO, fontSize: 20, color: C.fg3, whiteSpace: 'nowrap' }}>copperline · CPL-233 · run #482</div>

        {/* run status chip */}
        <div style={{
          position: 'absolute', right: 64, top: 222, display: 'flex', alignItems: 'center', gap: 12,
          background: approved ? 'rgba(75,196,111,0.10)' : C.orangeSoft,
          border: `1.5px solid ${approved ? 'rgba(75,196,111,0.55)' : C.orange}`,
          borderRadius: 100, padding: '14px 26px',
        }}>
          {!approved && (
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={C.orange} strokeWidth="2.4" strokeLinecap="round"><path d="M12 3a9 9 0 1 0 9 9"><animateTransform attributeName="transform" type="rotate" from="0 12 12" to="360 12 12" dur="0.9s" repeatCount="indefinite" /></path></svg>
          )}
          {approved && <div style={{ width: 24, height: 24, borderRadius: '50%', background: C.green, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Check size={15} /></div>}
          <span style={{ fontFamily: FMONO, fontSize: 20, color: approved ? C.green : C.orangeHi, whiteSpace: 'nowrap' }}>{chipLabel}</span>
        </div>

        {/* ── DAG ── */}
        <NodeCard t={t} at={0.15} x={64} y={420} w={952} h={130} step="step 1/4" title="Plan" sub="scope · approach" state={n1} />
        <Connector t={t} at={1.2} x={537} y={550} h={64} />

        <NodeCard t={t} at={0.3} x={64} y={614} w={952} h={200} step="step 2/4" title="Implement" sub="3 sandboxes" state={n2}>
          {/* progress bar — holds at 60% through the crash, resumes from 60% */}
          <div style={{ position: 'absolute', left: 84, right: 130, top: 140, height: 10, borderRadius: 5, background: C.border }}>
            <div style={{ position: 'absolute', left: 0, top: 0, height: 10, width: `${(prog * 100).toFixed(2)}%`, borderRadius: 5, background: C.orange }} />
            {t >= 2.9 && <div style={{ position: 'absolute', left: '60%', top: -4, width: 2, height: 18, background: 'rgba(209,207,205,0.45)' }} />}
          </div>
          <div style={{ position: 'absolute', right: 24, top: 130, fontFamily: FMONO, fontSize: 20, color: C.fg2 }}>{Math.round(prog * 100)}%</div>
          {resumeE > 0 && (
            <div style={{
              position: 'absolute', right: 24, top: 62, opacity: resumeE, transform: `translateY(${(1 - Easing.easeOutCubic(resumeE)) * 12}px)`,
              display: 'flex', alignItems: 'center', gap: 8, padding: '8px 16px', borderRadius: 100,
              border: '1.5px solid rgba(75,196,111,0.55)', background: 'rgba(75,196,111,0.10)',
            }}>
              <Check size={13} color={C.green} stroke={3.5} />
              <span style={{ fontFamily: FMONO, fontSize: 16, color: C.green, whiteSpace: 'nowrap' }}>resumed · nothing lost</span>
            </div>
          )}
        </NodeCard>
        <Connector t={t} at={6.4} x={537} y={814} h={64} />

        <NodeCard t={t} at={0.45} x={64} y={878} w={952} h={184} step="step 3/4" title="Open PR · CI" sub="copperline/app #519" state={n3}>
          <div style={{ position: 'absolute', left: 84, top: 114, display: 'flex', gap: 14 }}>
            <CiChip label="build" on={t >= 7.6} />
            <CiChip label="test" on={t >= 8.4} />
            <CiChip label="lint" on={t >= 9.2} />
          </div>
        </NodeCard>
        <Connector t={t} at={9.8} x={537} y={1062} h={64} />

        <NodeCard t={t} at={0.6} x={64} y={1126} w={952} h={200} step="step 4/4" title="Human approval gate" sub="requested · deploy to prod" state={n4}>
          {/* gate chip: grey → amber pulse → green */}
          <div style={{
            position: 'absolute', left: 84, top: 128, display: 'flex', alignItems: 'center', gap: 9, padding: '9px 18px', borderRadius: 100,
            border: `1.5px solid ${approved ? 'rgba(75,196,111,0.55)' : n4 === 'active' ? `rgba(223,163,60,${(0.3 + 0.35 * waitPulse).toFixed(3)})` : C.border}`,
            background: approved ? 'rgba(75,196,111,0.10)' : n4 === 'active' ? 'rgba(223,163,60,0.10)' : C.surface,
          }}>
            {approved && <Check size={14} color={C.green} stroke={3.5} />}
            <span style={{ fontFamily: FMONO, fontSize: 16, letterSpacing: '0.05em', whiteSpace: 'nowrap', color: approved ? C.green : n4 === 'active' ? AMBER : C.fg3 }}>
              {approved ? 'APPROVED' : n4 === 'active' ? 'WAITING FOR APPROVAL · 23h window' : 'APPROVAL REQUIRED'}
            </span>
          </div>
          {/* approve button */}
          <div style={{
            position: 'absolute', right: 24, top: 118, width: 180, height: 56, borderRadius: 12,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
            opacity: n4 === 'idle' ? 0.35 : 1,
            transform: `scale(${pressed ? 0.96 : 1})`,
            background: approved ? 'rgba(75,196,111,0.14)' : C.orange,
            border: `1.5px solid ${approved ? 'rgba(75,196,111,0.55)' : C.orange}`,
          }}>
            {approved && <Check size={18} color={C.green} stroke={3.5} />}
            <span style={{ fontFamily: FDISP, fontSize: 22, fontWeight: 700, color: approved ? C.green : C.black }}>{approved ? 'Approved' : 'Approve'}</span>
          </div>
        </NodeCard>

        {/* summary strip */}
        {summaryE > 0 && (
          <div style={{
            position: 'absolute', left: 64, top: 1420, width: 952, height: 96,
            opacity: summaryE, transform: `translateY(${(1 - Easing.easeOutBack(summaryE)) * 24}px)`,
            background: C.elevated, border: `1.5px solid ${C.borderStrong}`, borderRadius: 18,
            display: 'flex', alignItems: 'center', gap: 16, padding: '0 28px',
          }}>
            <div style={{ width: 30, height: 30, borderRadius: '50%', background: C.green, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><Check size={17} /></div>
            <span style={{ fontFamily: FMONO, fontSize: 24, color: C.white, whiteSpace: 'nowrap' }}>run #482 · survived 1 restart · 0 steps repeated</span>
          </div>
        )}
        {calloutE > 0 && (
          <div style={{ position: 'absolute', left: 64, top: 1560, width: 952, opacity: calloutE }}>
            <span style={{ fontFamily: FTEXT, fontSize: 26, fontWeight: 300, color: C.fg2 }}>
              State lives in the history. <span style={{ color: C.white, fontWeight: 500 }}>Workers are disposable.</span>
            </span>
          </div>
        )}

        {/* cursor → Approve */}
        {curOn && (
          <>
            <ClickRing x={902} y={1272} t0={13.0} localTime={t} />
            <Cursor x={curX} y={curY} opacity={curOp} pressed={pressed} />
          </>
        )}
      </World>

      {/* disaster dim overlay (screen-space, under banner + chrome) */}
      {dimO > 0 && <div style={{ position: 'absolute', inset: 0, background: C.black, opacity: dimO, zIndex: 10, pointerEvents: 'none' }} />}

      {/* disaster banner (screen-space, slides down under chrome) */}
      {bannerOn && (
        <div style={{
          position: 'absolute', left: 0, top: 140, width: VW, height: 96, zIndex: 15,
          transform: `translateY(${bannerY}px)`,
          background: C.elevated, borderTop: '1.5px solid rgba(229,83,75,0.4)', borderBottom: '1.5px solid rgba(229,83,75,0.4)',
          display: 'flex', alignItems: 'center', gap: 18, padding: '0 48px',
          boxShadow: '0 18px 50px rgba(0,0,0,0.5)',
        }}>
          <div style={{ width: 12, height: 12, borderRadius: '50%', background: RED, flexShrink: 0 }} />
          <span style={{ fontFamily: FMONO, fontSize: 24, color: C.white, whiteSpace: 'nowrap' }}>deploy · web-3 restarting</span>
          <span style={{ fontFamily: FMONO, fontSize: 17, color: RED, marginLeft: 'auto', letterSpacing: '0.06em', whiteSpace: 'nowrap' }}>SIGTERM</span>
        </div>
      )}
    </div>
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
          Temporal-backed. Crash-safe. Waits for humans.
        </div>
        <div style={{ fontFamily: FMONO, fontSize: 22, color: C.fg2, opacity: tagE, letterSpacing: '0.02em' }}>aixle.com</div>
      </div>
    </div>
  );
}

function DurableAd() {
  const t = useTime();
  return (
    <div style={{ position: 'absolute', inset: 0, background: C.black }}>
      <Sprite start={0} end={18}><DurableScene /></Sprite>
      <Sprite start={0} end={18}><Chrome title="Run #482 · Aixle Flow" url="flow.aixle.com/runs/482" /></Sprite>
      <Sprite start={18} end={20}><EndCard /></Sprite>
    </div>
  );
}
window.DurableAd = DurableAd;

function Movie() {
  const { Stage } = window;
  return React.createElement(Stage, { width: 1080, height: 1920, duration: 20, background: C.black, persistKey: 'aixle-durable-v' },
    React.createElement(DurableAd));
}
window.Movie = Movie;
