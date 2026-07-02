// scene-triggers-wide.jsx — "Start from anywhere" 16:9 (1920x1080, 20s)
// Wide re-layout of the triggers anthology: chapters in a centered 1200px
// stage, header top-left, progress ribbon bottom-center → endcard.
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
// interpolate with the input clamped to the keyframe range (no extrapolation)
const seg = (t, ks, vs, e = ease) => interpolate(ks, vs, e)(clamp(t, ks[0], ks[ks.length - 1]));

function Check({ size = 20, color = C.black, stroke = 3 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round">
      <path d="M20 6L9 17l-5-5" />
    </svg>
  );
}
function Bolt({ size = 18, color = C.orange }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill={color} stroke="none">
      <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z" />
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

// small orange bolt chip: "trigger fired" / "run started"
function TriggerChip({ t, at, label }) {
  const e = clamp((t - at) / 0.45, 0, 1);
  if (e <= 0) return null;
  const s = Easing.easeOutBack(e);
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 9, background: C.orangeSoft, border: `1.5px solid ${C.orange}`, borderRadius: 100, padding: '9px 20px', opacity: e, transform: `scale(${0.9 + 0.1 * s})` }}>
      <Bolt size={17} />
      <span style={{ fontFamily: FMONO, fontSize: 17, color: C.orangeHi, whiteSpace: 'nowrap' }}>{label}</span>
    </div>
  );
}

// ── shared bottom progress ribbon ──
function RibbonChip({ t, at, label, pulse }) {
  const done = t >= at;
  const e = clamp((t - at) / 0.4, 0, 1);
  const s = Easing.easeOutBack(e);
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 11, background: C.elevated, border: `1.5px solid ${done ? 'rgba(75,196,111,0.5)' : C.border}`, borderRadius: 100, padding: '10px 20px', transform: `scale(${pulse})` }}>
      <div style={{ position: 'relative', width: 26, height: 26, flexShrink: 0 }}>
        <div style={{ position: 'absolute', inset: 0, borderRadius: '50%', border: `2px solid ${C.borderStrong}` }} />
        {e > 0 && (
          <div style={{ position: 'absolute', inset: 0, borderRadius: '50%', background: C.green, display: 'flex', alignItems: 'center', justifyContent: 'center', transform: `scale(${s})` }}>
            <Check size={14} />
          </div>
        )}
      </div>
      <span style={{ fontFamily: FMONO, fontSize: 17, color: done ? C.white : C.fg3, whiteSpace: 'nowrap' }}>{label}</span>
    </div>
  );
}

function Ribbon({ t }) {
  const en = clamp((t - 0.4) / 0.5, 0, 1);
  const pulse = seg(t, [17.4, 17.65, 17.95], [1, 1.07, 1]);
  const items = [
    { label: 'Board', at: 3.4 },
    { label: 'Slack', at: 7.9 },
    { label: 'Webhook', at: 12.3 },
    { label: 'Schedule', at: 16.7 },
  ];
  return (
    <div style={{ position: 'absolute', left: 360, top: 930, width: 1200, opacity: en, display: 'flex', justifyContent: 'center', gap: 18 }}>
      {items.map((it) => <RibbonChip key={it.label} t={t} at={it.at} label={it.label} pulse={pulse} />)}
    </div>
  );
}

// persistent header + ribbon overlay (not camera-driven, stays crisp)
function Frame() {
  const { localTime: t } = useSprite();
  const hE = clamp(t / 0.6, 0, 1);
  const hy = (1 - Easing.easeOutCubic(hE)) * 18;
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      <div style={{ position: 'absolute', inset: 0, opacity: hE, transform: `translateY(${hy}px)` }}>
        <div style={{ position: 'absolute', left: 64, top: 140, fontFamily: FDISP, fontSize: 12, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase' }}>Automations</div>
        <div style={{ position: 'absolute', left: 62, top: 164, fontFamily: FDISP, fontSize: 46, fontWeight: 400, letterSpacing: '-0.02em', color: C.white, whiteSpace: 'nowrap' }}>Start from anywhere</div>
        <div style={{ position: 'absolute', left: 64, top: 240, fontFamily: FMONO, fontSize: 17, color: C.fg3, whiteSpace: 'nowrap' }}>copperline · wf_8sK2</div>
      </div>
      <Ribbon t={t} />
    </div>
  );
}

// ── chapter 1 · BOARD (sprite 0–4.2) ──
function ChapterBoard() {
  const { localTime: t } = useSprite();
  const dur = 4.2;
  const scale = seg(t, [0, dur], [1.0, 1.045]);
  const fx = seg(t, [0, 1.0, 2.3, dur], [930, 930, 985, 985]);
  const fy = 555;
  const enL = clamp(t / 0.45, 0, 1), en = Easing.easeOutCubic(enL);
  const exL = clamp((t - (dur - 0.4)) / 0.35, 0, 1), ex = Easing.easeInOutCubic(exL);
  const tx = seg(t, [1.1, 2.15], [0, 640]);
  const snap = seg(t, [2.15, 2.32, 2.6], [1, 1.045, 1]);
  const glow = seg(t, [2.15, 2.45, 3.3], [0, 0.55, 0]);
  const moved = t >= 2.15;

  const col = (x, name, count) => (
    <div style={{ position: 'absolute', left: x, top: 300, width: 560, height: 440, background: C.surface, border: `1px solid ${C.border}`, borderRadius: 18 }}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '18px 22px' }}>
        <span style={{ fontFamily: FDISP, fontSize: 20, fontWeight: 500, color: C.white, whiteSpace: 'nowrap' }}>{name}</span>
        <span style={{ fontFamily: FMONO, fontSize: 15, color: C.fg3, marginLeft: 'auto' }}>{count}</span>
      </div>
    </div>
  );
  const ghost = (x, title, id) => (
    <div style={{ position: 'absolute', left: x, top: 496, width: 528, background: C.elevated, border: `1px solid ${C.border}`, borderRadius: 12, padding: '14px 20px' }}>
      <div style={{ fontFamily: FMONO, fontSize: 13, color: C.fg3 }}>{id}</div>
      <div style={{ fontFamily: FDISP, fontSize: 20, color: C.fg2, marginTop: 5, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</div>
    </div>
  );

  return (
    <World scale={scale} fx={fx} fy={fy}>
      <div style={{ position: 'absolute', inset: 0, opacity: enL * (1 - exL), transform: `translateY(${(1 - en) * 24 - ex * 24}px)` }}>
        <div style={{ position: 'absolute', left: 360, top: 252, width: 1200, textAlign: 'center', fontFamily: FDISP, fontSize: 12, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase', whiteSpace: 'nowrap' }}>Trigger 01 · Board</div>

        {col(360, 'Design', moved ? '1' : '2')}
        {col(1000, 'Implementation', moved ? '2' : '1')}
        {/* arrival glow on the Implementation column */}
        <div style={{ position: 'absolute', left: 1000, top: 300, width: 560, height: 440, border: `1.5px solid ${C.orange}`, borderRadius: 18, opacity: glow }} />

        {ghost(376, 'Empty states audit', 'CPL-224')}
        {ghost(1016, 'Rate limit dashboard', 'CPL-219')}

        {/* the moving card: Design → Implementation */}
        <div style={{ position: 'absolute', left: 376, top: 368, width: 528, transform: `translateX(${tx}px) scale(${snap})`, background: C.elevated, border: `1.5px solid ${C.orange}`, borderRadius: 12, padding: '14px 20px', boxShadow: '0 14px 36px rgba(0,0,0,0.45)' }}>
          <div style={{ fontFamily: FMONO, fontSize: 13, color: C.orangeHi }}>CPL-231</div>
          <div style={{ fontFamily: FDISP, fontSize: 22, color: C.white, marginTop: 6, whiteSpace: 'nowrap' }}>Nightly usage report</div>
        </div>

        <div style={{ position: 'absolute', left: 1000, top: 764 }}><TriggerChip t={t} at={2.7} label="run started" /></div>

        <div style={{ position: 'absolute', left: 360, top: 845, width: 1200, textAlign: 'center', opacity: clamp((t - 2.9) / 0.4, 0, 1), fontFamily: FTEXT, fontSize: 24, fontWeight: 300, color: C.fg2, whiteSpace: 'nowrap' }}>
          Card hits Implementation. <span style={{ color: C.white, fontWeight: 500 }}>A run starts.</span>
        </div>
      </div>
    </World>
  );
}

// ── chapter 2 · SLACK (sprite 4.2–8.6) ──
function ChapterSlack() {
  const { localTime: t } = useSprite();
  const dur = 4.4;
  const scale = seg(t, [0, dur], [1.0, 1.05]);
  const fx = 960;
  const fy = seg(t, [0, dur], [565, 548]);
  const enL = clamp(t / 0.45, 0, 1), en = Easing.easeOutCubic(enL);
  const exL = clamp((t - (dur - 0.4)) / 0.35, 0, 1), ex = Easing.easeInOutCubic(exL);
  const pop = Easing.easeOutBack(clamp(t / 0.55, 0, 1));
  const msgE = clamp((t - 0.5) / 0.4, 0, 1);

  return (
    <World scale={scale} fx={fx} fy={fy}>
      <div style={{ position: 'absolute', inset: 0, opacity: enL * (1 - exL), transform: `translateY(${(1 - en) * 24 - ex * 24}px)` }}>
        <div style={{ position: 'absolute', left: 360, top: 252, width: 1200, textAlign: 'center', fontFamily: FDISP, fontSize: 12, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase', whiteSpace: 'nowrap' }}>Trigger 02 · Slack</div>

        {/* Slack-style message toast */}
        <div style={{ position: 'absolute', left: 560, top: 320, width: 800, transform: `scale(${0.93 + 0.07 * pop})`, transformOrigin: '50% 20%', background: C.elevated, border: `1px solid ${C.border}`, borderRadius: 20, overflow: 'hidden', boxShadow: '0 24px 60px rgba(0,0,0,0.55)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '14px 22px', background: C.surface, borderBottom: `1px solid ${C.border}` }}>
            <span style={{ fontFamily: FMONO, fontSize: 19, color: C.orange }}>#</span>
            <span style={{ fontFamily: FDISP, fontSize: 19, fontWeight: 600, color: C.white }}>support</span>
            <span style={{ fontFamily: FMONO, fontSize: 12, color: C.fg3, marginLeft: 'auto', border: `1px solid ${C.border}`, borderRadius: 6, padding: '2px 9px', letterSpacing: '0.08em' }}>SLACK</span>
          </div>
          <div style={{ display: 'flex', gap: 16, padding: '18px 22px' }}>
            <div style={{ width: 48, height: 48, borderRadius: 10, background: C.orange, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              <span style={{ fontFamily: FDISP, fontSize: 17, fontWeight: 700, color: C.black }}>DR</span>
            </div>
            <div>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 11 }}>
                <span style={{ fontFamily: FDISP, fontSize: 19, fontWeight: 600, color: C.white, whiteSpace: 'nowrap' }}>Dana Reyes</span>
                <span style={{ fontFamily: FMONO, fontSize: 13, color: C.fg3 }}>9:14 AM</span>
              </div>
              <div style={{ fontFamily: FTEXT, fontSize: 24, color: C.white, marginTop: 7, opacity: msgE, whiteSpace: 'nowrap' }}>My CSV export keeps failing.</div>
            </div>
          </div>
        </div>

        <div style={{ position: 'absolute', left: 560, top: 524, width: 800, display: 'flex', justifyContent: 'center' }}>
          <TriggerChip t={t} at={1.7} label="trigger fired" />
        </div>
        <div style={{ position: 'absolute', left: 560, top: 596, width: 800, textAlign: 'center', fontFamily: FMONO, fontSize: 16, color: C.fg3, opacity: clamp((t - 2.4) / 0.4, 0, 1), whiteSpace: 'nowrap' }}>workflow wf_8sK2 · run #1041 started</div>

        <div style={{ position: 'absolute', left: 360, top: 845, width: 1200, textAlign: 'center', opacity: clamp((t - 2.9) / 0.4, 0, 1), fontFamily: FTEXT, fontSize: 24, fontWeight: 300, color: C.fg2, whiteSpace: 'nowrap' }}>
          A message in #support. <span style={{ color: C.white, fontWeight: 500 }}>A run starts.</span>
        </div>
      </div>
    </World>
  );
}

// ── chapter 3 · WEBHOOK (sprite 8.6–13) ──
function ChapterWebhook() {
  const { localTime: t } = useSprite();
  const dur = 4.4;
  const scale = seg(t, [0, dur], [1.0, 1.045]);
  const fx = 960;
  const fy = 552;
  const enL = clamp(t / 0.45, 0, 1), en = Easing.easeOutCubic(enL);
  const exL = clamp((t - (dur - 0.4)) / 0.35, 0, 1), ex = Easing.easeInOutCubic(exL);

  return (
    <World scale={scale} fx={fx} fy={fy}>
      <div style={{ position: 'absolute', inset: 0, opacity: enL * (1 - exL), transform: `translateY(${(1 - en) * 24 - ex * 24}px)` }}>
        <div style={{ position: 'absolute', left: 360, top: 252, width: 1200, textAlign: 'center', fontFamily: FDISP, fontSize: 12, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase', whiteSpace: 'nowrap' }}>Trigger 03 · Webhook</div>

        <div style={{ position: 'absolute', left: 360, top: 330, width: 1200, height: 230, background: C.termBg, border: `1.5px solid ${C.borderStrong}`, borderRadius: 20, overflow: 'hidden', boxShadow: '0 24px 60px rgba(0,0,0,0.55)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '12px 20px', background: C.surface, borderBottom: `1px solid ${C.border}` }}>
            <div style={{ display: 'flex', gap: 6 }}>
              <div style={{ width: 11, height: 11, borderRadius: '50%', background: C.orange }} />
              <div style={{ width: 11, height: 11, borderRadius: '50%', background: '#3a3733' }} />
              <div style={{ width: 11, height: 11, borderRadius: '50%', background: '#3a3733' }} />
            </div>
            <span style={{ fontFamily: FMONO, fontSize: 15, color: C.fg2, marginLeft: 6 }}>webhook · hooks/wf_8sK2</span>
            <span style={{ fontFamily: FMONO, fontSize: 12, color: C.orangeHi, marginLeft: 'auto', border: `1px solid rgba(224,88,46,0.4)`, borderRadius: 6, padding: '2px 9px', letterSpacing: '0.06em' }}>POST</span>
          </div>
          <div style={{ padding: '16px 24px 8px' }}>
            <TLine t={t} at={0.7} size={18} text={`curl -X POST https://flow.aixle.com/hooks/wf_8sK2 -d '{"event":"deploy"}'`} />
            <TLine t={t} at={2.55} size={18} prefix="" text="202 Accepted · run started" />
            <TLine t={t} at={3.2} size={18} prefix="  " text="live view · runs/1042" dim showCursor />
          </div>
        </div>

        <div style={{ position: 'absolute', left: 360, top: 845, width: 1200, textAlign: 'center', opacity: clamp((t - 3.1) / 0.4, 0, 1), fontFamily: FTEXT, fontSize: 24, fontWeight: 300, color: C.fg2, whiteSpace: 'nowrap' }}>
          One POST. <span style={{ color: C.white, fontWeight: 500 }}>A run starts.</span>
        </div>
      </div>
    </World>
  );
}

// ── chapter 4 · SCHEDULE (sprite 13–17.4) ──
function ChapterSchedule() {
  const { localTime: t } = useSprite();
  const dur = 4.4;
  const scale = seg(t, [0, dur], [1.0, 1.05]);
  const fx = 960;
  const fy = seg(t, [0, dur], [565, 548]);
  const enL = clamp(t / 0.45, 0, 1), en = Easing.easeOutCubic(enL);
  const exL = clamp((t - (dur - 0.4)) / 0.35, 0, 1), ex = Easing.easeInOutCubic(exL);
  const f = Easing.easeInOutCubic(clamp((t - 1.5) / 0.45, 0, 1));

  return (
    <World scale={scale} fx={fx} fy={fy}>
      <div style={{ position: 'absolute', inset: 0, opacity: enL * (1 - exL), transform: `translateY(${(1 - en) * 24 - ex * 24}px)` }}>
        <div style={{ position: 'absolute', left: 360, top: 252, width: 1200, textAlign: 'center', fontFamily: FDISP, fontSize: 12, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase', whiteSpace: 'nowrap' }}>Trigger 04 · Schedule</div>

        <div style={{ position: 'absolute', left: 560, top: 292, width: 800, height: 470, background: C.surface, border: `1px solid ${C.border}`, borderRadius: 22 }}>
          <div style={{ position: 'absolute', left: 0, right: 0, top: 26, textAlign: 'center', fontFamily: FMONO, fontSize: 13, color: C.fg3, letterSpacing: '0.12em' }}>CRON SCHEDULE</div>
          <div style={{ position: 'absolute', left: 0, right: 0, top: 66, textAlign: 'center', fontFamily: FMONO, fontSize: 44, color: C.white, letterSpacing: '0.04em', whiteSpace: 'nowrap' }}>0 9 * * 1-5</div>
          <div style={{ position: 'absolute', left: 0, right: 0, top: 134, textAlign: 'center', fontFamily: FTEXT, fontSize: 19, color: C.fg3, whiteSpace: 'nowrap' }}>weekdays at 09:00</div>

          {/* orange pulse ring at the flip */}
          {t >= 1.55 && (
            <div style={{ position: 'absolute', left: '50%', top: 296, width: 240, height: 240, borderRadius: '50%', border: `2px solid ${C.orange}`, transform: `translate(-50%,-50%) scale(${seg(t, [1.55, 2.5], [0.85, 1.5], Easing.easeOutQuad)})`, opacity: seg(t, [1.55, 2.5], [0.5, 0], Easing.easeOutQuad) }} />
          )}
          {/* 08:59 → 09:00 crossfade flip */}
          <div style={{ position: 'absolute', left: 0, right: 0, top: 250, textAlign: 'center', fontFamily: FMONO, fontSize: 88, color: C.white, letterSpacing: '0.02em', opacity: 1 - f, transform: `translateY(${-20 * f}px)`, whiteSpace: 'nowrap' }}>08:59</div>
          <div style={{ position: 'absolute', left: 0, right: 0, top: 250, textAlign: 'center', fontFamily: FMONO, fontSize: 88, color: C.orangeHi, letterSpacing: '0.02em', opacity: f, transform: `translateY(${20 * (1 - f)}px)`, whiteSpace: 'nowrap' }}>09:00</div>

          <div style={{ position: 'absolute', left: 0, right: 0, top: 392, display: 'flex', justifyContent: 'center' }}>
            <TriggerChip t={t} at={2.6} label="run started" />
          </div>
        </div>

        <div style={{ position: 'absolute', left: 360, top: 845, width: 1200, textAlign: 'center', opacity: clamp((t - 3.0) / 0.4, 0, 1), fontFamily: FTEXT, fontSize: 24, fontWeight: 300, color: C.fg2, whiteSpace: 'nowrap' }}>
          09:00 on weekdays. <span style={{ color: C.white, fontWeight: 500 }}>A run starts.</span>
        </div>
      </div>
    </World>
  );
}

function EndCard() {
  const { localTime: t } = useSprite();
  const ringScale = interpolate([0, 2], [1.0, 1.12], Easing.easeOutQuad)(t);
  const ringRot = t * 6;
  const logoE = clamp((t - 0.3) / 0.6, 0, 1);
  const tagE = clamp((t - 0.7) / 0.6, 0, 1);
  const tag2E = clamp((t - 1.0) / 0.6, 0, 1);
  return (
    <div style={{ position: 'absolute', inset: 0, background: C.black, overflow: 'hidden' }}>
      <img src="assets/Ring_Orange.png" alt="" style={{ position: 'absolute', left: '50%', top: 400, width: 860, height: 860, transform: `translate(-50%,-50%) scale(${ringScale}) rotate(${ringRot}deg)`, opacity: 0.9, objectFit: 'contain' }} />
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(circle at 50% 32%, transparent 26%, rgba(10,9,8,0.55) 56%, #0A0908 80%)' }} />
      <div style={{ position: 'absolute', left: 0, right: 0, top: 645, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 22 }}>
        <img src="assets/logo-wordmark-white.svg" alt="Aixle" style={{ width: 340, opacity: logoE, transform: `translateY(${(1 - Easing.easeOutCubic(logoE)) * 20}px)` }} />
        <div style={{ fontFamily: FDISP, fontWeight: 700, fontSize: 26, letterSpacing: '0.42em', color: C.orange, marginTop: -14, marginLeft: '0.42em', opacity: logoE }}>FLOW</div>
        <div style={{ maxWidth: 900, textAlign: 'center', fontFamily: FDISP, fontSize: 36, fontWeight: 400, letterSpacing: '-0.02em', color: C.white, lineHeight: 1.12, opacity: tagE, transform: `translateY(${(1 - Easing.easeOutCubic(tagE)) * 16}px)`, whiteSpace: 'nowrap' }}>
          Board. Slack. Webhook. Schedule.
        </div>
        <div style={{ maxWidth: 820, textAlign: 'center', fontFamily: FTEXT, fontSize: 23, fontWeight: 300, color: C.fg2, opacity: tag2E, transform: `translateY(${(1 - Easing.easeOutCubic(tag2E)) * 14}px)`, whiteSpace: 'nowrap' }}>
          Runs start where your work happens.
        </div>
        <div style={{ fontFamily: FMONO, fontSize: 19, color: C.fg2, opacity: tag2E, letterSpacing: '0.02em' }}>aixle.com</div>
      </div>
    </div>
  );
}

function TriggersAdWide() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: C.black }}>
      <Sprite start={0} end={4.2}><ChapterBoard /></Sprite>
      <Sprite start={4.2} end={8.6}><ChapterSlack /></Sprite>
      <Sprite start={8.6} end={13.0}><ChapterWebhook /></Sprite>
      <Sprite start={13.0} end={17.4}><ChapterSchedule /></Sprite>
      <Sprite start={0} end={18}><Frame /></Sprite>
      <Sprite start={0} end={18}><Chrome title="copperline · Aixle Flow" url="flow.aixle.com/copperline/automations" /></Sprite>
      <Sprite start={18} end={20}><EndCard /></Sprite>
    </div>
  );
}
window.TriggersAdWide = TriggersAdWide;

function Movie() {
  const { Stage } = window;
  return React.createElement(Stage, { width: 1920, height: 1080, duration: 20, background: C.black, persistKey: 'aixle-triggers-w' },
    React.createElement(TriggersAdWide));
}
window.Movie = Movie;
