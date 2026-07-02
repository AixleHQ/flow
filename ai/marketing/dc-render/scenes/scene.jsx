// scene.jsx — "Browser + triggers + AI workflow" vertical social ad (1080x1920)
// Reads the animation engine globals (Stage, Sprite, useSprite, Easing,
// interpolate) set by animations.jsx. Aixle design system: warm near-black,
// off-white type, single orange accent, Swiss type.
const { Sprite, useSprite, useTime, Easing, interpolate, clamp } = window;

// ── Aixle tokens ────────────────────────────────────────────────────────────
const C = {
  black: '#0A0908',
  surface: '#191817',
  elevated: '#1C1A18',
  border: '#292726',
  borderStrong: '#393837',
  white: '#D1CFCD',
  fg2: '#9F9D9C',
  fg3: '#7F7E7C',
  orange: '#E0582E',
  orangeSoft: 'rgba(224,88,46,0.14)',
};
const FDISP = "'Hanken Grotesk','Helvetica Neue',Helvetica,Arial,sans-serif";
const FTEXT = "'Figtree','Helvetica Neue',Helvetica,Arial,sans-serif";
const FMONO = "'Spline Sans Mono',ui-monospace,monospace";

const VW = 1080, VH = 1920;
const ease = Easing.easeInOutCubic;

// ── small helpers ─────────────────────────────────────────────────────────
const lerp = (a, b, t) => a + (b - a) * t;

// ── Icons ───────────────────────────────────────────────────────────────────
function SlackIcon({ size = 34 }) {
  const s = size / 24;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" style={{ display: 'block' }}>
      <path fill="#36C5F0" d="M6.5 15a2 2 0 1 1-2-2h2v2z" />
      <path fill="#36C5F0" d="M7.5 15a2 2 0 0 1 4 0v5a2 2 0 1 1-4 0v-5z" />
      <path fill="#2EB67D" d="M9.5 6.5a2 2 0 1 1 2 2h-2v-2z" />
      <path fill="#2EB67D" d="M9.5 7.5a2 2 0 0 1 0 4h-5a2 2 0 1 1 0-4h5z" />
      <path fill="#ECB22E" d="M17.5 9.5a2 2 0 1 1 2 2h-2v-2z" />
      <path fill="#ECB22E" d="M16.5 9.5a2 2 0 0 1-4 0v-5a2 2 0 1 1 4 0v5z" />
      <path fill="#E01E5A" d="M14.5 17.5a2 2 0 1 1-2-2h2v2z" />
      <path fill="#E01E5A" d="M14.5 16.5a2 2 0 0 1 0-4h5a2 2 0 1 1 0 4h-5z" />
    </svg>
  );
}
function SparkIcon({ size = 30, color = C.orange }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" style={{ display: 'block' }}>
      <path d="M12 2c.6 4.8 2.2 6.4 7 7-4.8.6-6.4 2.2-7 7-.6-4.8-2.2-6.4-7-7 4.8-.6 6.4-2.2 7-7z" fill={color} />
      <path d="M19 3c.2 1.6.7 2.1 2.3 2.3-1.6.2-2.1.7-2.3 2.3-.2-1.6-.7-2.1-2.3-2.3C18.3 5.1 18.8 4.6 19 3z" fill={color} opacity="0.7" />
    </svg>
  );
}
function ColumnsIcon({ size = 28, color = C.white }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="4" width="5" height="16" rx="1" /><rect x="10" y="4" width="5" height="10" rx="1" /><rect x="17" y="4" width="4" height="13" rx="1" />
    </svg>
  );
}
function WebhookIcon({ size = 28, color = C.white }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M18 13a5 5 0 0 0-10 0" /><path d="M6 16h6" /><circle cx="6" cy="16" r="2.4" /><circle cx="18" cy="16" r="2.4" /><path d="M18 16h.01M9 8l3 5" />
    </svg>
  );
}
function ClockIcon({ size = 28, color = C.white }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" />
    </svg>
  );
}
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

// ── Browser chrome (persistent frame) ───────────────────────────────────────
function Chrome({ title, url }) {
  return (
    <div style={{ position: 'absolute', left: 0, top: 0, width: VW, height: 122, zIndex: 20 }}>
      {/* tab strip */}
      <div style={{ position: 'absolute', top: 0, left: 0, width: VW, height: 60, background: '#000', display: 'flex', alignItems: 'flex-end', paddingLeft: 26 }}>
        <div style={{ display: 'flex', gap: 9, position: 'absolute', top: 22, left: 26 }}>
          {['#3f3d3b', '#3f3d3b', '#3f3d3b'].map((c, i) => <div key={i} style={{ width: 13, height: 13, borderRadius: '50%', background: c }} />)}
        </div>
        <div style={{ marginLeft: 118, marginBottom: 0, height: 44, background: C.surface, borderRadius: '10px 10px 0 0', display: 'flex', alignItems: 'center', gap: 10, padding: '0 18px', maxWidth: 420 }}>
          <div style={{ width: 16, height: 16, borderRadius: 4, background: C.orange, flexShrink: 0 }} />
          <span style={{ fontFamily: FDISP, fontSize: 18, color: C.white, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</span>
        </div>
      </div>
      {/* toolbar */}
      <div style={{ position: 'absolute', top: 60, left: 0, width: VW, height: 62, background: C.surface, borderBottom: `1px solid ${C.border}`, display: 'flex', alignItems: 'center', gap: 18, padding: '0 30px' }}>
        <div style={{ display: 'flex', gap: 22, color: C.fg3 }}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M15 5l-7 7 7 7" /></svg>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 5l7 7-7 7" /></svg>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7M3 4v4h4" /></svg>
        </div>
        <div style={{ flex: 1, height: 40, background: C.black, border: `1px solid ${C.border}`, borderRadius: 20, display: 'flex', alignItems: 'center', gap: 10, padding: '0 18px' }}>
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={C.fg3} strokeWidth="2"><rect x="4" y="9" width="16" height="12" rx="2" /><path d="M8 9V6a4 4 0 0 1 8 0v3" /></svg>
          <span style={{ fontFamily: FMONO, fontSize: 16, color: C.fg2, letterSpacing: '0.01em' }}>{url}</span>
        </div>
      </div>
    </div>
  );
}

// ── World wrapper with camera transform ─────────────────────────────────────
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

// ════════════════════════════════════════════════════════════════════════════
// SCENE 1 — Trigger picker
// ════════════════════════════════════════════════════════════════════════════
const TRIGGERS = [
  { icon: 'slack', title: 'Slack message', sub: 'When a message is posted to a channel' },
  { icon: 'columns', title: 'Card moved', sub: 'When a card enters a board column' },
  { icon: 'webhook', title: 'Incoming webhook', sub: 'When an HTTP request is received' },
  { icon: 'clock', title: 'Schedule', sub: 'Run on a recurring cron schedule' },
];
const CARD_X = 64, CARD_W = 952, CARD_H = 150, CARD_Y0 = 430, CARD_STEP = 182;
const cardTop = (i) => CARD_Y0 + i * CARD_STEP;
const cardCenterY = (i) => cardTop(i) + CARD_H / 2;

function TriggerScene() {
  const { localTime: t } = useSprite();

  // camera
  const scale = interpolate([0, 0.6, 3.2, 4.2, 5.5], [1.06, 1.12, 1.12, 1.34, 1.32], ease)(t);
  const fy = interpolate([0, 3.2, 4.2, 5.5], [820, 790, 505, 505], ease)(t);
  const fx = 540;

  // cursor
  const cx = interpolate([0.3, 1.0, 1.5, 2.1, 2.7, 3.2, 5.5], [900, 300, 300, 300, 300, 300, 300], Easing.easeInOutCubic)(t);
  const cy = interpolate([0.3, 1.0, 1.5, 2.1, 2.7, 3.2, 5.5], [1560, cardCenterY(2), cardCenterY(3), cardCenterY(1), cardCenterY(0), cardCenterY(0), cardCenterY(0)], Easing.easeInOutCubic)(t);
  const clickT = 3.2;
  const selected = t >= clickT + 0.05;
  const pressed = t >= clickT && t < clickT + 0.12;

  // which card is hovered (nearest by cursor y) before selection
  let hover = -1;
  if (t > 0.9 && !selected) {
    let best = 1e9;
    for (let i = 0; i < 4; i++) { const d = Math.abs(cy - cardCenterY(i)); if (d < best && d < 100) { best = d; hover = i; } }
  }

  return (
    <World scale={scale} fx={fx} fy={fy}>
      {/* header */}
      <div style={{ position: 'absolute', left: 64, top: 196, fontFamily: FDISP, fontSize: 13, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase' }}>New automation</div>
      <div style={{ position: 'absolute', left: 62, top: 224, fontFamily: FDISP, fontSize: 66, fontWeight: 400, letterSpacing: '-0.02em', color: C.white, lineHeight: 1.02, whiteSpace: 'nowrap' }}>Choose a trigger</div>
      <div style={{ position: 'absolute', left: 64, top: 326, fontFamily: FTEXT, fontSize: 26, fontWeight: 300, color: C.fg2 }}>What should kick off this workflow?</div>

      {/* cards */}
      {TRIGGERS.map((tr, i) => {
        const isSel = selected && i === 0;
        const isHover = hover === i;
        const dim = selected && i !== 0 ? 0.4 : 1;
        const enter = clamp((t - (0.15 + i * 0.09)) / 0.4, 0, 1);
        const ey = (1 - Easing.easeOutCubic(enter)) * 26;
        return (
          <div key={i} style={{
            position: 'absolute', left: CARD_X, top: cardTop(i), width: CARD_W, height: CARD_H,
            opacity: enter * dim, transform: `translateY(${ey}px) scale(${isSel ? 1.015 : 1})`,
            background: isSel ? 'rgba(224,88,46,0.08)' : C.elevated,
            border: `${isSel ? 2 : 1}px solid ${isSel ? C.orange : isHover ? C.borderStrong : C.border}`,
            borderRadius: 24, display: 'flex', alignItems: 'center', gap: 28, padding: '0 34px',
            boxShadow: isSel ? '0 0 0 6px rgba(224,88,46,0.10)' : 'none', transition: 'none',
          }}>
            <div style={{ width: 74, height: 74, borderRadius: 18, background: C.surface, border: `1px solid ${C.border}`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              {tr.icon === 'slack' && <SlackIcon size={40} />}
              {tr.icon === 'columns' && <ColumnsIcon size={34} color={C.fg2} />}
              {tr.icon === 'webhook' && <WebhookIcon size={34} color={C.fg2} />}
              {tr.icon === 'clock' && <ClockIcon size={34} color={C.fg2} />}
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: FDISP, fontSize: 34, fontWeight: 500, color: C.white, letterSpacing: '-0.01em' }}>{tr.title}</div>
              <div style={{ fontFamily: FTEXT, fontSize: 22, fontWeight: 300, color: C.fg2, marginTop: 4 }}>{tr.sub}</div>
            </div>
            {isSel
              ? <div style={{ width: 44, height: 44, borderRadius: '50%', background: C.orange, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><Check size={24} color={C.black} /></div>
              : <div style={{ width: 30, height: 30, borderRadius: '50%', border: `2px solid ${C.border}`, flexShrink: 0 }} />}
          </div>
        );
      })}

      {/* confirm bar */}
      {selected && (() => {
        const e = clamp((t - (clickT + 0.25)) / 0.4, 0, 1);
        return (
          <div style={{ position: 'absolute', left: 64, top: cardTop(3) + 40, width: CARD_W, opacity: Easing.easeOutCubic(e), transform: `translateY(${(1 - e) * 14}px)`, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <span style={{ fontFamily: FTEXT, fontSize: 24, color: C.fg2 }}>Trigger added — build the flow</span>
            <div style={{ background: C.white, color: C.black, fontFamily: FDISP, fontWeight: 500, fontSize: 24, padding: '18px 40px', borderRadius: 100 }}>Continue</div>
          </div>
        );
      })()}

      <ClickRing x={cx} y={cy} t0={clickT} localTime={t} />
      <Cursor x={cx} y={cy} pressed={pressed} />
    </World>
  );
}

// ════════════════════════════════════════════════════════════════════════════
// SCENE 2 — Workflow build + run
// ════════════════════════════════════════════════════════════════════════════
const NODES = [
  { icon: 'slack', title: 'Message posted', sub: '#support channel', trigger: true },
  { icon: 'ai', title: 'Summarize thread', sub: 'Claude reads the message' },
  { icon: 'ai', title: 'Classify intent', sub: 'Bug · Billing · How-to', output: 'Bug report' },
  { icon: 'ai', title: 'Draft reply', sub: 'On-brand, cites docs', output: 'Reply ready' },
  { icon: 'slack', title: 'Post reply', sub: 'Back to #support' },
];
const NW = 620, NX = (VW - NW) / 2, NH = 150, NY0 = 300, NSTEP = 208;
const nodeTop = (i) => NY0 + i * NSTEP;
const nodeMidY = (i) => nodeTop(i) + NH / 2;

// timing (local seconds within scene)
const APPEAR = [0.0, 0.5, 0.95, 1.4, 1.85];
const RUN_START = 3.6;
const ACTIVE = [ // [start,end] per node
  [3.7, 4.35], [4.35, 5.0], [5.0, 5.75], [5.75, 6.5], [6.5, 7.2],
];

function WorkflowScene() {
  const { localTime: t } = useSprite();

  const runState = (i) => {
    const [a, b] = ACTIVE[i];
    if (t < a) return 'idle';
    if (t <= b) return 'active';
    return 'done';
  };
  const running = t >= RUN_START;

  // ── camera ──
  const scale = interpolate(
    [0, 0.5, 2.6, 3.4, RUN_START, 4.35, 5.0, 5.75, 6.5, 7.3, 8.2, 12.5],
    [1.18, 1.1, 0.92, 0.92, 1.02, 1.04, 1.05, 1.06, 1.06, 1.0, 0.9, 0.9], ease)(t);
  const fy = interpolate(
    [0, 0.5, 2.6, 3.4, 3.7, 4.35, 5.0, 5.75, 6.5, 7.3, 8.2, 12.5],
    [420, 480, 760, 760, nodeMidY(0), nodeMidY(1), nodeMidY(2), nodeMidY(3), nodeMidY(4), 1180, 900, 900], ease)(t);
  const fx = 540;

  // ── cursor to Run ──
  const runBtnX = 540, runBtnHitX = 900, runBtnY = 205;
  const showCursor = t > 2.5 && t < 4.1;
  const ccx = interpolate([2.6, 3.35, 4.1], [980, runBtnHitX, runBtnHitX], Easing.easeInOutCubic)(t);
  const ccy = interpolate([2.6, 3.35, 4.1], [1450, runBtnY, runBtnY], Easing.easeInOutCubic)(t);
  const cursorClickT = 3.45;
  const cursorOp = interpolate([2.5, 2.8, 3.9, 4.1], [0, 1, 1, 0], Easing.linear)(t);

  // Run button appears at ~2.3, glows once running
  const runBtnEnter = clamp((t - 2.2) / 0.4, 0, 1);

  return (
    <World scale={scale} fx={fx} fy={fy}>
      {/* header */}
      <div style={{ position: 'absolute', left: 64, top: 168, fontFamily: FDISP, fontSize: 13, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase' }}>Workflow</div>
      <div style={{ position: 'absolute', left: 62, top: 194, fontFamily: FDISP, fontSize: 52, fontWeight: 400, letterSpacing: '-0.02em', color: C.white, whiteSpace: 'nowrap' }}>Slack triage</div>
      {/* Run button */}
      <div style={{
        position: 'absolute', right: 64, top: 182, opacity: runBtnEnter, transform: `scale(${lerp(0.9, 1, Easing.easeOutBack(runBtnEnter))})`, transformOrigin: 'center',
        background: running ? C.orange : C.white, color: running ? C.white : C.black,
        fontFamily: FDISP, fontWeight: 500, fontSize: 26, padding: '18px 38px', borderRadius: 100,
        display: 'flex', alignItems: 'center', gap: 12,
        boxShadow: running ? '0 0 0 8px rgba(224,88,46,0.12)' : 'none',
      }}>
        {running
          ? <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round"><path d="M12 3a9 9 0 1 0 9 9"><animateTransform attributeName="transform" type="rotate" from="0 12 12" to="360 12 12" dur="0.9s" repeatCount="indefinite" /></path></svg>
          : <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z" /></svg>}
        {running ? 'Running' : 'Run'}
      </div>

      {/* connectors */}
      {NODES.slice(1).map((_, k) => {
        const i = k + 1;
        const drawFrom = APPEAR[i] - 0.08;
        const draw = clamp((t - drawFrom) / 0.3, 0, 1);
        const y1 = nodeTop(i - 1) + NH, y2 = nodeTop(i);
        const filled = running && runState(i - 1) === 'done';
        return (
          <div key={i} style={{ position: 'absolute', left: 540 - 2, top: y1, width: 4, height: (y2 - y1), background: C.border, transformOrigin: 'top', transform: `scaleY(${draw})`, borderRadius: 2 }}>
            <div style={{ position: 'absolute', inset: 0, background: C.orange, transformOrigin: 'top', transform: `scaleY(${filled ? 1 : 0})`, transition: 'transform 0.35s ease', borderRadius: 2 }} />
          </div>
        );
      })}

      {/* nodes */}
      {NODES.map((n, i) => {
        const enter = clamp((t - APPEAR[i]) / 0.4, 0, 1);
        if (enter <= 0) return null;
        const ee = Easing.easeOutBack(enter);
        const st = running ? runState(i) : 'idle';
        const active = st === 'active';
        const done = st === 'done';
        const showOut = n.output && (done || active);
        // active pulse
        const pulse = active ? 0.5 + 0.5 * Math.sin((t - ACTIVE[i][0]) * 9) : 0;
        return (
          <div key={i} style={{
            position: 'absolute', left: NX, top: nodeTop(i), width: NW, height: NH,
            opacity: enter, transform: `translateY(${(1 - ee) * 22}px) scale(${lerp(0.94, 1, ee) * (active ? 1.02 : 1)})`, transformOrigin: 'center',
            background: C.elevated, borderRadius: 22,
            border: `${active ? 2 : 1}px solid ${active ? C.orange : done ? 'rgba(224,88,46,0.5)' : C.border}`,
            boxShadow: active ? `0 0 0 ${6 + pulse * 8}px rgba(224,88,46,${0.06 + pulse * 0.10})` : 'none',
            display: 'flex', alignItems: 'center', gap: 24, padding: '0 30px', overflow: 'visible',
          }}>
            {n.trigger && <div style={{ position: 'absolute', left: 0, top: 22, bottom: 22, width: 5, background: C.orange, borderRadius: 3 }} />}
            <div style={{ width: 68, height: 68, borderRadius: 16, background: C.surface, border: `1px solid ${C.border}`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              {n.icon === 'slack' && <SlackIcon size={36} />}
              {n.icon === 'ai' && <SparkIcon size={32} />}
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <span style={{ fontFamily: FDISP, fontSize: 32, fontWeight: 500, color: C.white, letterSpacing: '-0.01em', whiteSpace: 'nowrap' }}>{n.title}</span>
                {n.trigger && <span style={{ fontFamily: FDISP, fontSize: 15, fontWeight: 700, letterSpacing: '0.08em', color: C.orange, textTransform: 'uppercase', border: `1px solid ${C.orange}`, borderRadius: 100, padding: '3px 12px' }}>Trigger</span>}
              </div>
              <div style={{ fontFamily: FTEXT, fontSize: 22, fontWeight: 300, color: C.fg2, marginTop: 4, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{n.sub}</div>
            </div>
            {/* status chip */}
            {showOut
              ? <div style={{ display: 'flex', alignItems: 'center', gap: 8, background: C.orangeSoft, border: `1px solid rgba(224,88,46,0.4)`, borderRadius: 100, padding: '8px 16px', flexShrink: 0 }}>
                  <span style={{ fontFamily: FMONO, fontSize: 18, color: C.orange }}>{n.output}</span>
                </div>
              : done
              ? <div style={{ width: 40, height: 40, borderRadius: '50%', background: 'rgba(224,88,46,0.9)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><Check size={22} color={C.black} /></div>
              : active
              ? <div style={{ width: 40, height: 40, flexShrink: 0 }}><svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke={C.orange} strokeWidth="2.4" strokeLinecap="round"><path d="M12 3a9 9 0 1 0 9 9"><animateTransform attributeName="transform" type="rotate" from="0 12 12" to="360 12 12" dur="0.8s" repeatCount="indefinite" /></path></svg></div>
              : null}
          </div>
        );
      })}

      {/* incoming Slack message toast (feeds the trigger) */}
      {(() => {
        const e = clamp((t - 3.0) / 0.45, 0, 1);
        const out = clamp((t - 4.6) / 0.4, 0, 1);
        if (e <= 0) return null;
        const op = Easing.easeOutCubic(e) * (1 - out);
        return (
          <div style={{ position: 'absolute', left: NX, top: 150, width: NW, opacity: op, transform: `translateY(${(1 - Easing.easeOutCubic(e)) * -20 - out * 14}px)`, display: 'flex', alignItems: 'center', gap: 16, background: C.surface, border: `1px solid ${C.border}`, borderRadius: 18, padding: '16px 22px', boxShadow: '0 18px 44px rgba(0,0,0,0.5)' }}>
            <SlackIcon size={30} />
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: FDISP, fontSize: 18, fontWeight: 600, color: C.white }}>#support · new message</div>
              <div style={{ fontFamily: FTEXT, fontSize: 21, fontWeight: 300, color: C.fg2, marginTop: 2 }}>“My CSV export keeps failing.”</div>
            </div>
          </div>
        );
      })()}

      {/* posted reply result */}
      {(() => {
        const e = clamp((t - 7.2) / 0.5, 0, 1);
        if (e <= 0) return null;
        const ee = Easing.easeOutBack(e);
        return (
          <div style={{
            position: 'absolute', left: NX - 20, top: nodeTop(4) + NH + 40, width: NW + 40,
            opacity: clamp(e * 1.4, 0, 1), transform: `translateY(${(1 - ee) * 24}px)`,
            background: C.elevated, border: `1px solid ${C.border}`, borderRadius: 22, padding: '26px 30px',
            boxShadow: '0 20px 50px rgba(0,0,0,0.5)',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 14 }}>
              <div style={{ width: 46, height: 46, borderRadius: 12, background: C.orange, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <span style={{ fontFamily: FDISP, fontWeight: 700, fontSize: 24, color: C.black }}>A</span>
              </div>
              <div>
                <span style={{ fontFamily: FDISP, fontSize: 24, fontWeight: 600, color: C.white }}>Aixle Flow</span>
                <span style={{ fontFamily: FMONO, fontSize: 15, color: C.fg3, marginLeft: 10, background: C.surface, padding: '3px 8px', borderRadius: 6 }}>APP</span>
                <span style={{ fontFamily: FTEXT, fontSize: 18, color: C.fg3, marginLeft: 10 }}>replied in #support</span>
              </div>
            </div>
            <div style={{ fontFamily: FTEXT, fontSize: 24, fontWeight: 300, color: C.white, lineHeight: 1.4 }}>
              Thanks for flagging this — I’ve logged it as a bug <span style={{ color: C.orange, fontFamily: FMONO, fontSize: 21 }}>AIX-4821</span> and the team is on it. Here’s a workaround in the meantime.
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 18, fontFamily: FDISP, fontSize: 19, color: C.orange }}>
              <div style={{ width: 26, height: 26, borderRadius: '50%', background: C.orange, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Check size={16} color={C.black} /></div>
              Auto-replied in 3.2s
            </div>
          </div>
        );
      })()}

      {showCursor && <><ClickRing x={ccx} y={ccy} t0={cursorClickT} localTime={t} /><Cursor x={ccx} y={ccy} opacity={cursorOp} pressed={t >= cursorClickT && t < cursorClickT + 0.12} /></>}
    </World>
  );
}

// ════════════════════════════════════════════════════════════════════════════
// SCENE 3 — Endcard
// ════════════════════════════════════════════════════════════════════════════
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
        <div style={{ maxWidth: 800, textAlign: 'center', fontFamily: FDISP, fontSize: 42, fontWeight: 400, letterSpacing: '-0.02em', color: C.white, lineHeight: 1.12, opacity: tagE, transform: `translateY(${(1 - Easing.easeOutCubic(tagE)) * 18}px)` }}>
          From a Slack message to a sent reply — automatically.
        </div>
        <div style={{ fontFamily: FMONO, fontSize: 22, color: C.fg2, opacity: tagE, letterSpacing: '0.02em' }}>aixle.com</div>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════════════
function BrowserTriggers() {
  const t = useTime();
  const chromeTitle = t < 5.5 ? 'New automation · Aixle Flow' : 'Slack triage · Aixle Flow';
  const chromeUrl = t < 5.5 ? 'flow.aixle.com/automations/new' : 'flow.aixle.com/w/slack-triage';
  return (
    <div style={{ position: 'absolute', inset: 0, background: C.black }}>
      {/* content behind chrome */}
      <Sprite start={0} end={5.5}><TriggerScene /></Sprite>
      <Sprite start={5.5} end={18}><WorkflowScene /></Sprite>
      {/* persistent chrome over content, hidden on endcard */}
      <Sprite start={0} end={18} keepMounted={false}>
        <Chrome title={chromeTitle} url={chromeUrl} />
      </Sprite>
      <Sprite start={18} end={20}><EndCard /></Sprite>
    </div>
  );
}

window.BrowserTriggers = BrowserTriggers;

function Movie() {
  const { Stage } = window;
  return React.createElement(Stage, { width: 1080, height: 1920, duration: 20, background: C.black, persistKey: 'aixle-triggers' },
    React.createElement(BrowserTriggers));
}
window.Movie = Movie;
