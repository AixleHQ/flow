// scene-durable-wide.jsx — "Runs that survive" 16:9 (1920x1080, 20s)
// Wide re-layout: 4-node DAG column left, Temporal event-history terminal right,
// summary strip bottom-right. Same durable story: crash → resume from checkpoint.
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
const VW = 1920, VH = 1080;
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
      <svg width="36" height="36" viewBox="0 0 24 24" fill="none">
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

// ── DAG building blocks ─────────────────────────────────────────────────────
function StatusDot({ state, size = 30 }) {
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
      opacity: e, transform: `translateY(${(1 - ee) * 20}px)`,
      background: C.elevated, border, borderRadius: 16,
    }}>
      <div style={{ position: 'absolute', left: 20, top: 22 }}><StatusDot state={state} /></div>
      <div style={{ position: 'absolute', left: 68, top: 20, fontFamily: FDISP, fontSize: 25, fontWeight: 500, color: C.white, whiteSpace: 'nowrap' }}>{title}</div>
      {sub && <div style={{ position: 'absolute', left: 68, top: 58, fontFamily: FMONO, fontSize: 14, color: C.fg3, whiteSpace: 'nowrap' }}>{sub}</div>}
      <div style={{ position: 'absolute', right: 20, top: 26, fontFamily: FMONO, fontSize: 13, color: C.fg3, whiteSpace: 'nowrap' }}>{step}</div>
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
      display: 'flex', alignItems: 'center', gap: 8, padding: '6px 14px', borderRadius: 100,
      border: `1.5px solid ${on ? 'rgba(75,196,111,0.55)' : C.border}`,
      background: on ? 'rgba(75,196,111,0.10)' : C.surface,
    }}>
      {on ? <Check size={12} color={C.green} stroke={3.5} /> : <div style={{ width: 7, height: 7, borderRadius: '50%', background: C.fg3 }} />}
      <span style={{ fontFamily: FMONO, fontSize: 14, color: on ? C.green : C.fg3 }}>{label}</span>
    </div>
  );
}

// ── Temporal event history (right column) ───────────────────────────────────
function EventLog({ t }) {
  return (
    <div style={{
      position: 'absolute', left: 960, top: 300, width: 896, height: 592,
      background: C.termBg, border: `1.5px solid ${C.borderStrong}`, borderRadius: 20, overflow: 'hidden',
      boxShadow: '0 24px 60px rgba(0,0,0,0.55)',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '12px 20px', background: C.surface, borderBottom: `1px solid ${C.border}` }}>
        <div style={{ display: 'flex', gap: 6 }}>
          <div style={{ width: 11, height: 11, borderRadius: '50%', background: C.orange }} />
          <div style={{ width: 11, height: 11, borderRadius: '50%', background: '#3a3733' }} />
          <div style={{ width: 11, height: 11, borderRadius: '50%', background: '#3a3733' }} />
        </div>
        <span style={{ fontFamily: FMONO, fontSize: 15, color: C.fg2, marginLeft: 6 }}>event history · temporal</span>
        <span style={{ fontFamily: FMONO, fontSize: 12, color: C.orangeHi, marginLeft: 'auto', border: `1px solid rgba(224,88,46,0.4)`, borderRadius: 6, padding: '2px 9px', letterSpacing: '0.06em' }}>DURABLE</span>
      </div>
      <div style={{ padding: '14px 22px 8px' }}>
        <TLine t={t} at={0.5} prefix="▸ " text="run #482 · started" color={C.fg2} size={15} />
        <TLine t={t} at={1.3} prefix="  " text="plan · completed" dim size={15} />
        <TLine t={t} at={1.8} prefix="  " text="implement · started · 3 sandboxes" dim size={15} />
        <TLine t={t} at={2.9} prefix="  " text="checkpoint saved · progress 60%" size={15} />
        <TLine t={t} at={3.5} prefix="  " text="worker web-3 lost · SIGTERM" color={RED} size={15} />
        <TLine t={t} at={4.8} prefix="  " text="resumed from checkpoint · 0 steps repeated" size={15} />
        <TLine t={t} at={6.5} prefix="  " text="implement · completed" dim size={15} />
        <TLine t={t} at={7.7} prefix="  " text="ci · build passed" dim size={15} />
        <TLine t={t} at={8.5} prefix="  " text="ci · test passed" dim size={15} />
        <TLine t={t} at={9.3} prefix="  " text="ci · lint passed" dim size={15} />
        <TLine t={t} at={10.5} prefix="  " text="waiting for approval · window 23h" color={AMBER} size={15} />
        <TLine t={t} at={13.2} prefix="  " text="approved · gate released" size={15} />
        <TLine t={t} at={15.0} prefix="▸ " text="run #482 · complete" color={C.fg2} showCursor size={15} />
      </div>
    </div>
  );
}

function DurableSceneWide() {
  const { localTime: t } = useSprite();

  // phases: 0-3 run starts · 3-4.5 disaster · 4.5-6 resume · 6-10 CI · 10-15 gate · 15-18 summary
  const baseScale = interpolate([0, 0.6, 6.6, 7.4, 10.2, 11.0, 14.6, 15.4, 18], [1.1, 1.16, 1.16, 1.08, 1.08, 1.06, 1.06, 0.95, 0.95], ease)(t);
  const dagPulse = interpolate([13.15, 13.4, 13.7], [1, 1.015, 1], ease)(clamp(t, 13.15, 13.7));
  const scale = baseScale * dagPulse;
  const fx = interpolate([0, 6.6, 7.4, 10.2, 11.0, 14.6, 15.4, 18], [600, 600, 680, 680, 720, 720, 960, 960], ease)(t);
  const fy = interpolate([0, 6.6, 7.4, 10.2, 11.0, 14.6, 15.4, 18], [480, 480, 630, 630, 760, 760, 560, 560], ease)(t);

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
  const bannerY = interpolate([3.0, 3.45, 4.1, 4.55], [-220, 0, 0, -220], ease)(clamp(t, 3.0, 4.55));
  const bannerOn = t >= 3.0 && t <= 4.55;

  // cursor → Approve
  const curOn = t >= 11.6 && t <= 14.2;
  const curX = interpolate([11.6, 12.9], [1020, 784], ease)(clamp(t, 11.6, 12.9));
  const curY = interpolate([11.6, 12.9], [1050, 918], ease)(clamp(t, 11.6, 12.9));
  const curOp = clamp((t - 11.6) / 0.4, 0, 1) * (1 - clamp((t - 13.6) / 0.4, 0, 1));
  const pressed = t >= 13.0 && t < 13.12;

  // gate chip pulse (calm)
  const waitPulse = 0.5 + 0.5 * Math.sin(t * Math.PI * 2 / 1.8);

  // run status chip
  let chipLabel = 'run #482 · running';
  if (t >= 3.2 && t < 4.8) chipLabel = 'worker lost · resuming';
  if (approved) chipLabel = 'run #482 · complete';

  const summaryE = clamp((t - 14.8) / 0.5, 0, 1);

  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      <World scale={scale} fx={fx} fy={fy}>
        {/* header */}
        <div style={{ position: 'absolute', left: 64, top: 150, fontFamily: FDISP, fontSize: 12, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase' }}>Durable orchestration</div>
        <div style={{ position: 'absolute', left: 62, top: 174, fontFamily: FDISP, fontSize: 46, fontWeight: 400, letterSpacing: '-0.02em', color: C.white, whiteSpace: 'nowrap' }}>Runs that survive</div>
        <div style={{ position: 'absolute', left: 64, top: 246, fontFamily: FMONO, fontSize: 17, color: C.fg3, whiteSpace: 'nowrap' }}>copperline · CPL-233 · run #482</div>

        {/* run status chip */}
        <div style={{
          position: 'absolute', left: 520, top: 178, display: 'flex', alignItems: 'center', gap: 11,
          background: approved ? 'rgba(75,196,111,0.10)' : C.orangeSoft,
          border: `1.5px solid ${approved ? 'rgba(75,196,111,0.55)' : C.orange}`,
          borderRadius: 100, padding: '11px 22px',
        }}>
          {!approved && (
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke={C.orange} strokeWidth="2.4" strokeLinecap="round"><path d="M12 3a9 9 0 1 0 9 9"><animateTransform attributeName="transform" type="rotate" from="0 12 12" to="360 12 12" dur="0.9s" repeatCount="indefinite" /></path></svg>
          )}
          {approved && <div style={{ width: 21, height: 21, borderRadius: '50%', background: C.green, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Check size={13} /></div>}
          <span style={{ fontFamily: FMONO, fontSize: 17, color: approved ? C.green : C.orangeHi, whiteSpace: 'nowrap' }}>{chipLabel}</span>
        </div>

        {/* ── DAG column (left) ── */}
        <NodeCard t={t} at={0.15} x={64} y={300} w={830} h={104} step="step 1/4" title="Plan" sub="scope · approach" state={n1} />
        <Connector t={t} at={1.2} x={477} y={404} h={44} />

        <NodeCard t={t} at={0.3} x={64} y={448} w={830} h={150} step="step 2/4" title="Implement" sub="3 sandboxes" state={n2}>
          {/* progress bar — holds at 60% through the crash, resumes from 60% */}
          <div style={{ position: 'absolute', left: 68, right: 110, top: 106, height: 8, borderRadius: 4, background: C.border }}>
            <div style={{ position: 'absolute', left: 0, top: 0, height: 8, width: `${(prog * 100).toFixed(2)}%`, borderRadius: 4, background: C.orange }} />
            {t >= 2.9 && <div style={{ position: 'absolute', left: '60%', top: -4, width: 2, height: 16, background: 'rgba(209,207,205,0.45)' }} />}
          </div>
          <div style={{ position: 'absolute', right: 20, top: 96, fontFamily: FMONO, fontSize: 16, color: C.fg2 }}>{Math.round(prog * 100)}%</div>
          {resumeE > 0 && (
            <div style={{
              position: 'absolute', right: 20, top: 50, opacity: resumeE, transform: `translateY(${(1 - Easing.easeOutCubic(resumeE)) * 10}px)`,
              display: 'flex', alignItems: 'center', gap: 7, padding: '6px 12px', borderRadius: 100,
              border: '1.5px solid rgba(75,196,111,0.55)', background: 'rgba(75,196,111,0.10)',
            }}>
              <Check size={11} color={C.green} stroke={3.5} />
              <span style={{ fontFamily: FMONO, fontSize: 13, color: C.green, whiteSpace: 'nowrap' }}>resumed · nothing lost</span>
            </div>
          )}
        </NodeCard>
        <Connector t={t} at={6.4} x={477} y={598} h={44} />

        <NodeCard t={t} at={0.45} x={64} y={642} w={830} h={132} step="step 3/4" title="Open PR · CI" sub="copperline/app #519" state={n3}>
          <div style={{ position: 'absolute', left: 68, top: 86, display: 'flex', gap: 12 }}>
            <CiChip label="build" on={t >= 7.6} />
            <CiChip label="test" on={t >= 8.4} />
            <CiChip label="lint" on={t >= 9.2} />
          </div>
        </NodeCard>
        <Connector t={t} at={9.8} x={477} y={774} h={44} />

        <NodeCard t={t} at={0.6} x={64} y={818} w={830} h={150} step="step 4/4" title="Human approval gate" sub="requested · deploy to prod" state={n4}>
          {/* gate chip: grey → amber pulse → green */}
          <div style={{
            position: 'absolute', left: 68, top: 98, display: 'flex', alignItems: 'center', gap: 8, padding: '7px 14px', borderRadius: 100,
            border: `1.5px solid ${approved ? 'rgba(75,196,111,0.55)' : n4 === 'active' ? `rgba(223,163,60,${(0.3 + 0.35 * waitPulse).toFixed(3)})` : C.border}`,
            background: approved ? 'rgba(75,196,111,0.10)' : n4 === 'active' ? 'rgba(223,163,60,0.10)' : C.surface,
          }}>
            {approved && <Check size={12} color={C.green} stroke={3.5} />}
            <span style={{ fontFamily: FMONO, fontSize: 13, letterSpacing: '0.05em', whiteSpace: 'nowrap', color: approved ? C.green : n4 === 'active' ? AMBER : C.fg3 }}>
              {approved ? 'APPROVED' : n4 === 'active' ? 'WAITING FOR APPROVAL · 23h window' : 'APPROVAL REQUIRED'}
            </span>
          </div>
          {/* approve button */}
          <div style={{
            position: 'absolute', right: 20, top: 88, width: 156, height: 48, borderRadius: 11,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9,
            opacity: n4 === 'idle' ? 0.35 : 1,
            transform: `scale(${pressed ? 0.96 : 1})`,
            background: approved ? 'rgba(75,196,111,0.14)' : C.orange,
            border: `1.5px solid ${approved ? 'rgba(75,196,111,0.55)' : C.orange}`,
          }}>
            {approved && <Check size={15} color={C.green} stroke={3.5} />}
            <span style={{ fontFamily: FDISP, fontSize: 19, fontWeight: 700, color: approved ? C.green : C.black }}>{approved ? 'Approved' : 'Approve'}</span>
          </div>
        </NodeCard>

        {/* ── event history (right) ── */}
        <EventLog t={t} />

        {/* summary strip (bottom right) */}
        {summaryE > 0 && (
          <div style={{
            position: 'absolute', left: 960, top: 912, width: 896, height: 72,
            opacity: summaryE, transform: `translateY(${(1 - Easing.easeOutBack(summaryE)) * 20}px)`,
            background: C.elevated, border: `1.5px solid ${C.borderStrong}`, borderRadius: 16,
            display: 'flex', alignItems: 'center', gap: 14, padding: '0 24px',
          }}>
            <div style={{ width: 26, height: 26, borderRadius: '50%', background: C.green, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><Check size={15} /></div>
            <span style={{ fontFamily: FMONO, fontSize: 19, color: C.white, whiteSpace: 'nowrap' }}>run #482 · survived 1 restart · 0 steps repeated</span>
          </div>
        )}

        {/* cursor → Approve */}
        {curOn && (
          <>
            <ClickRing x={796} y={930} t0={13.0} localTime={t} />
            <Cursor x={curX} y={curY} opacity={curOp} pressed={pressed} />
          </>
        )}
      </World>

      {/* disaster dim overlay (screen-space, under banner + chrome) */}
      {dimO > 0 && <div style={{ position: 'absolute', inset: 0, background: C.black, opacity: dimO, zIndex: 10, pointerEvents: 'none' }} />}

      {/* disaster banner (screen-space, slides down under chrome) */}
      {bannerOn && (
        <div style={{
          position: 'absolute', left: 0, top: 112, width: VW, height: 80, zIndex: 15,
          transform: `translateY(${bannerY}px)`,
          background: C.elevated, borderTop: '1.5px solid rgba(229,83,75,0.4)', borderBottom: '1.5px solid rgba(229,83,75,0.4)',
          display: 'flex', alignItems: 'center', gap: 16, padding: '0 44px',
          boxShadow: '0 18px 50px rgba(0,0,0,0.5)',
        }}>
          <div style={{ width: 11, height: 11, borderRadius: '50%', background: RED, flexShrink: 0 }} />
          <span style={{ fontFamily: FMONO, fontSize: 21, color: C.white, whiteSpace: 'nowrap' }}>deploy · web-3 restarting</span>
          <span style={{ fontFamily: FMONO, fontSize: 15, color: RED, marginLeft: 'auto', letterSpacing: '0.06em', whiteSpace: 'nowrap' }}>SIGTERM</span>
        </div>
      )}
    </div>
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
          Temporal-backed. Crash-safe. Waits for humans.
        </div>
        <div style={{ fontFamily: FMONO, fontSize: 19, color: C.fg2, opacity: tagE, letterSpacing: '0.02em' }}>aixle.com</div>
      </div>
    </div>
  );
}

function DurableAdWide() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: C.black }}>
      <Sprite start={0} end={18}><DurableSceneWide /></Sprite>
      <Sprite start={0} end={18}><Chrome title="Run #482 · Aixle Flow" url="flow.aixle.com/runs/482" /></Sprite>
      <Sprite start={18} end={20}><EndCard /></Sprite>
    </div>
  );
}
window.DurableAdWide = DurableAdWide;

function Movie() {
  const { Stage } = window;
  return React.createElement(Stage, { width: 1920, height: 1080, duration: 20, background: C.black, persistKey: 'aixle-durable-w' },
    React.createElement(DurableAdWide));
}
window.Movie = Movie;
