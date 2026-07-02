// scene-triggers.jsx — "Start from anywhere" vertical ad (1080x1920, 20s)
// Triggers anthology: Board → Slack → Webhook → Schedule. Each chapter shows
// the trigger firing, a shared bottom ribbon collects a green check → endcard.
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
function TLine({ t, at, speed = 46, prefix = '$ ', text, color = C.green, dim = false, showCursor = false, size = 21 }) {
  if (t < at) return null;
  const chars = Math.floor((t - at) * speed);
  const shown = text.slice(0, chars);
  const done = chars >= text.length;
  return (
    <div style={{ fontFamily: FMONO, fontSize: size, lineHeight: 1.8, color: dim ? C.greenDim : color, whiteSpace: 'pre' }}>
      {prefix}{shown}
      {(!done || showCursor) && <span style={{ display: 'inline-block', width: 11, height: 22, background: C.green, verticalAlign: -3, marginLeft: 2 }} />}
    </div>
  );
}

// small orange bolt chip: "trigger fired" / "run started"
function TriggerChip({ t, at, label }) {
  const e = clamp((t - at) / 0.45, 0, 1);
  if (e <= 0) return null;
  const s = Easing.easeOutBack(e);
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 10, background: C.orangeSoft, border: `1.5px solid ${C.orange}`, borderRadius: 100, padding: '12px 24px', opacity: e, transform: `scale(${0.9 + 0.1 * s})` }}>
      <Bolt size={19} />
      <span style={{ fontFamily: FMONO, fontSize: 19, color: C.orangeHi, whiteSpace: 'nowrap' }}>{label}</span>
    </div>
  );
}

// ── shared bottom progress ribbon ──
function RibbonChip({ t, at, label, pulse }) {
  const done = t >= at;
  const e = clamp((t - at) / 0.4, 0, 1);
  const s = Easing.easeOutBack(e);
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, background: C.elevated, border: `1.5px solid ${done ? 'rgba(75,196,111,0.5)' : C.border}`, borderRadius: 100, padding: '12px 22px', transform: `scale(${pulse})` }}>
      <div style={{ position: 'relative', width: 30, height: 30, flexShrink: 0 }}>
        <div style={{ position: 'absolute', inset: 0, borderRadius: '50%', border: `2px solid ${C.borderStrong}` }} />
        {e > 0 && (
          <div style={{ position: 'absolute', inset: 0, borderRadius: '50%', background: C.green, display: 'flex', alignItems: 'center', justifyContent: 'center', transform: `scale(${s})` }}>
            <Check size={16} />
          </div>
        )}
      </div>
      <span style={{ fontFamily: FMONO, fontSize: 19, color: done ? C.white : C.fg3, whiteSpace: 'nowrap' }}>{label}</span>
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
    <div style={{ position: 'absolute', left: 64, top: 1560, width: 952, opacity: en }}>
      <div style={{ fontFamily: FDISP, fontSize: 13, fontWeight: 700, letterSpacing: '0.1em', color: C.fg3, textTransform: 'uppercase', whiteSpace: 'nowrap' }}>Four ways to start a run</div>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 20 }}>
        {items.map((it) => <RibbonChip key={it.label} t={t} at={it.at} label={it.label} pulse={pulse} />)}
      </div>
    </div>
  );
}

// persistent header + ribbon overlay (not camera-driven, stays crisp)
function Frame() {
  const { localTime: t } = useSprite();
  const hE = clamp(t / 0.6, 0, 1);
  const hy = (1 - Easing.easeOutCubic(hE)) * 20;
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      <div style={{ position: 'absolute', inset: 0, opacity: hE, transform: `translateY(${hy}px)` }}>
        <div style={{ position: 'absolute', left: 64, top: 190, fontFamily: FDISP, fontSize: 13, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase' }}>Automations</div>
        <div style={{ position: 'absolute', left: 62, top: 218, fontFamily: FDISP, fontSize: 54, fontWeight: 400, letterSpacing: '-0.02em', color: C.white, whiteSpace: 'nowrap' }}>Start from anywhere</div>
        <div style={{ position: 'absolute', left: 64, top: 302, fontFamily: FMONO, fontSize: 20, color: C.fg3, whiteSpace: 'nowrap' }}>copperline · wf_8sK2</div>
      </div>
      <Ribbon t={t} />
    </div>
  );
}

// ── chapter 1 · BOARD (sprite 0–4.2) ──
function ChapterBoard() {
  const { localTime: t } = useSprite();
  const dur = 4.2;
  const scale = seg(t, [0, dur], [1.0, 1.05]);
  const fx = seg(t, [0, 1.0, 2.3, dur], [520, 520, 560, 560]);
  const fy = 880;
  const enL = clamp(t / 0.45, 0, 1), en = Easing.easeOutCubic(enL);
  const exL = clamp((t - (dur - 0.4)) / 0.35, 0, 1), ex = Easing.easeInOutCubic(exL);
  const tx = seg(t, [1.1, 2.15], [0, 492]);
  const snap = seg(t, [2.15, 2.32, 2.6], [1, 1.045, 1]);
  const glow = seg(t, [2.15, 2.45, 3.3], [0, 0.55, 0]);
  const moved = t >= 2.15;

  const col = (x, name, count) => (
    <div style={{ position: 'absolute', left: x, top: 480, width: 460, height: 620, background: C.surface, border: `1px solid ${C.border}`, borderRadius: 20 }}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '20px 24px' }}>
        <span style={{ fontFamily: FDISP, fontSize: 22, fontWeight: 500, color: C.white, whiteSpace: 'nowrap' }}>{name}</span>
        <span style={{ fontFamily: FMONO, fontSize: 16, color: C.fg3, marginLeft: 'auto' }}>{count}</span>
      </div>
    </div>
  );
  const ghost = (x, title, id) => (
    <div style={{ position: 'absolute', left: x, top: 724, width: 428, background: C.elevated, border: `1px solid ${C.border}`, borderRadius: 14, padding: '18px 22px' }}>
      <div style={{ fontFamily: FMONO, fontSize: 15, color: C.fg3 }}>{id}</div>
      <div style={{ fontFamily: FDISP, fontSize: 22, color: C.fg2, marginTop: 6, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</div>
    </div>
  );

  return (
    <World scale={scale} fx={fx} fy={fy}>
      <div style={{ position: 'absolute', inset: 0, opacity: enL * (1 - exL), transform: `translateY(${(1 - en) * 26 - ex * 26}px)` }}>
        <div style={{ position: 'absolute', left: 64, top: 420, fontFamily: FDISP, fontSize: 13, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase', whiteSpace: 'nowrap' }}>Trigger 01 · Board</div>

        {col(64, 'Design', moved ? '1' : '2')}
        {col(556, 'Implementation', moved ? '2' : '1')}
        {/* arrival glow on the Implementation column */}
        <div style={{ position: 'absolute', left: 556, top: 480, width: 460, height: 620, border: `1.5px solid ${C.orange}`, borderRadius: 20, opacity: glow }} />

        {ghost(80, 'Empty states audit', 'CPL-224')}
        {ghost(572, 'Rate limit dashboard', 'CPL-219')}

        {/* the moving card: Design → Implementation */}
        <div style={{ position: 'absolute', left: 80, top: 556, width: 428, transform: `translateX(${tx}px) scale(${snap})`, background: C.elevated, border: `1.5px solid ${C.orange}`, borderRadius: 14, padding: '18px 22px', boxShadow: '0 16px 40px rgba(0,0,0,0.45)' }}>
          <div style={{ fontFamily: FMONO, fontSize: 15, color: C.orangeHi }}>CPL-231</div>
          <div style={{ fontFamily: FDISP, fontSize: 24, color: C.white, marginTop: 8, whiteSpace: 'nowrap' }}>Nightly usage report</div>
        </div>

        <div style={{ position: 'absolute', left: 556, top: 1128 }}><TriggerChip t={t} at={2.7} label="run started" /></div>

        <div style={{ position: 'absolute', left: 64, top: 1256, width: 952, opacity: clamp((t - 2.9) / 0.4, 0, 1), fontFamily: FTEXT, fontSize: 27, fontWeight: 300, color: C.fg2, whiteSpace: 'nowrap' }}>
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
  const fx = 540;
  const fy = seg(t, [0, dur], [900, 880]);
  const enL = clamp(t / 0.45, 0, 1), en = Easing.easeOutCubic(enL);
  const exL = clamp((t - (dur - 0.4)) / 0.35, 0, 1), ex = Easing.easeInOutCubic(exL);
  const pop = Easing.easeOutBack(clamp(t / 0.55, 0, 1));
  const msgE = clamp((t - 0.5) / 0.4, 0, 1);

  return (
    <World scale={scale} fx={fx} fy={fy}>
      <div style={{ position: 'absolute', inset: 0, opacity: enL * (1 - exL), transform: `translateY(${(1 - en) * 26 - ex * 26}px)` }}>
        <div style={{ position: 'absolute', left: 64, top: 420, fontFamily: FDISP, fontSize: 13, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase', whiteSpace: 'nowrap' }}>Trigger 02 · Slack</div>

        {/* Slack-style message toast */}
        <div style={{ position: 'absolute', left: 104, top: 560, width: 872, transform: `scale(${0.93 + 0.07 * pop})`, transformOrigin: '50% 20%', background: C.elevated, border: `1px solid ${C.border}`, borderRadius: 22, overflow: 'hidden', boxShadow: '0 24px 60px rgba(0,0,0,0.55)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '18px 26px', background: C.surface, borderBottom: `1px solid ${C.border}` }}>
            <span style={{ fontFamily: FMONO, fontSize: 22, color: C.orange }}>#</span>
            <span style={{ fontFamily: FDISP, fontSize: 21, fontWeight: 600, color: C.white }}>support</span>
            <span style={{ fontFamily: FMONO, fontSize: 13, color: C.fg3, marginLeft: 'auto', border: `1px solid ${C.border}`, borderRadius: 6, padding: '3px 10px', letterSpacing: '0.08em' }}>SLACK</span>
          </div>
          <div style={{ display: 'flex', gap: 18, padding: '22px 26px' }}>
            <div style={{ width: 56, height: 56, borderRadius: 12, background: C.orange, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              <span style={{ fontFamily: FDISP, fontSize: 20, fontWeight: 700, color: C.black }}>DR</span>
            </div>
            <div>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 12 }}>
                <span style={{ fontFamily: FDISP, fontSize: 22, fontWeight: 600, color: C.white, whiteSpace: 'nowrap' }}>Dana Reyes</span>
                <span style={{ fontFamily: FMONO, fontSize: 15, color: C.fg3 }}>9:14 AM</span>
              </div>
              <div style={{ fontFamily: FTEXT, fontSize: 28, color: C.white, marginTop: 8, opacity: msgE, whiteSpace: 'nowrap' }}>My CSV export keeps failing.</div>
            </div>
          </div>
        </div>

        <div style={{ position: 'absolute', left: 104, top: 838 }}><TriggerChip t={t} at={1.7} label="trigger fired" /></div>
        <div style={{ position: 'absolute', left: 104, top: 926, fontFamily: FMONO, fontSize: 18, color: C.fg3, opacity: clamp((t - 2.4) / 0.4, 0, 1), whiteSpace: 'nowrap' }}>workflow wf_8sK2 · run #1041 started</div>

        <div style={{ position: 'absolute', left: 64, top: 1256, width: 952, opacity: clamp((t - 2.9) / 0.4, 0, 1), fontFamily: FTEXT, fontSize: 27, fontWeight: 300, color: C.fg2, whiteSpace: 'nowrap' }}>
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
  const fx = 540;
  const fy = seg(t, [0, dur], [890, 875]);
  const enL = clamp(t / 0.45, 0, 1), en = Easing.easeOutCubic(enL);
  const exL = clamp((t - (dur - 0.4)) / 0.35, 0, 1), ex = Easing.easeInOutCubic(exL);

  return (
    <World scale={scale} fx={fx} fy={fy}>
      <div style={{ position: 'absolute', inset: 0, opacity: enL * (1 - exL), transform: `translateY(${(1 - en) * 26 - ex * 26}px)` }}>
        <div style={{ position: 'absolute', left: 64, top: 420, fontFamily: FDISP, fontSize: 13, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase', whiteSpace: 'nowrap' }}>Trigger 03 · Webhook</div>

        <div style={{ position: 'absolute', left: 64, top: 560, width: 952, height: 260, background: C.termBg, border: `1.5px solid ${C.borderStrong}`, borderRadius: 22, overflow: 'hidden', boxShadow: '0 24px 60px rgba(0,0,0,0.55)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '14px 22px', background: C.surface, borderBottom: `1px solid ${C.border}` }}>
            <div style={{ display: 'flex', gap: 7 }}>
              <div style={{ width: 12, height: 12, borderRadius: '50%', background: C.orange }} />
              <div style={{ width: 12, height: 12, borderRadius: '50%', background: '#3a3733' }} />
              <div style={{ width: 12, height: 12, borderRadius: '50%', background: '#3a3733' }} />
            </div>
            <span style={{ fontFamily: FMONO, fontSize: 17, color: C.fg2, marginLeft: 8 }}>webhook · hooks/wf_8sK2</span>
            <span style={{ fontFamily: FMONO, fontSize: 14, color: C.orangeHi, marginLeft: 'auto', border: `1px solid rgba(224,88,46,0.4)`, borderRadius: 6, padding: '3px 10px', letterSpacing: '0.06em' }}>POST</span>
          </div>
          <div style={{ padding: '18px 26px 8px' }}>
            <TLine t={t} at={0.7} size={19} text={`curl -X POST https://flow.aixle.com/hooks/wf_8sK2 -d '{"event":"deploy"}'`} />
            <TLine t={t} at={2.55} size={19} prefix="" text="202 Accepted · run started" />
            <TLine t={t} at={3.2} size={19} prefix="  " text="live view · runs/1042" dim showCursor />
          </div>
        </div>

        <div style={{ position: 'absolute', left: 64, top: 1256, width: 952, opacity: clamp((t - 3.1) / 0.4, 0, 1), fontFamily: FTEXT, fontSize: 27, fontWeight: 300, color: C.fg2, whiteSpace: 'nowrap' }}>
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
  const fx = 540;
  const fy = seg(t, [0, dur], [900, 880]);
  const enL = clamp(t / 0.45, 0, 1), en = Easing.easeOutCubic(enL);
  const exL = clamp((t - (dur - 0.4)) / 0.35, 0, 1), ex = Easing.easeInOutCubic(exL);
  const f = Easing.easeInOutCubic(clamp((t - 1.5) / 0.45, 0, 1));

  return (
    <World scale={scale} fx={fx} fy={fy}>
      <div style={{ position: 'absolute', inset: 0, opacity: enL * (1 - exL), transform: `translateY(${(1 - en) * 26 - ex * 26}px)` }}>
        <div style={{ position: 'absolute', left: 64, top: 420, fontFamily: FDISP, fontSize: 13, fontWeight: 700, letterSpacing: '0.1em', color: C.orange, textTransform: 'uppercase', whiteSpace: 'nowrap' }}>Trigger 04 · Schedule</div>

        <div style={{ position: 'absolute', left: 104, top: 500, width: 872, height: 640, background: C.surface, border: `1px solid ${C.border}`, borderRadius: 24 }}>
          <div style={{ position: 'absolute', left: 0, right: 0, top: 36, textAlign: 'center', fontFamily: FMONO, fontSize: 16, color: C.fg3, letterSpacing: '0.12em' }}>CRON SCHEDULE</div>
          <div style={{ position: 'absolute', left: 0, right: 0, top: 92, textAlign: 'center', fontFamily: FMONO, fontSize: 56, color: C.white, letterSpacing: '0.04em', whiteSpace: 'nowrap' }}>0 9 * * 1-5</div>
          <div style={{ position: 'absolute', left: 0, right: 0, top: 182, textAlign: 'center', fontFamily: FTEXT, fontSize: 22, color: C.fg3, whiteSpace: 'nowrap' }}>weekdays at 09:00</div>

          {/* orange pulse ring at the flip */}
          {t >= 1.55 && (
            <div style={{ position: 'absolute', left: '50%', top: 380, width: 300, height: 300, borderRadius: '50%', border: `2px solid ${C.orange}`, transform: `translate(-50%,-50%) scale(${seg(t, [1.55, 2.5], [0.85, 1.5], Easing.easeOutQuad)})`, opacity: seg(t, [1.55, 2.5], [0.5, 0], Easing.easeOutQuad) }} />
          )}
          {/* 08:59 → 09:00 crossfade flip */}
          <div style={{ position: 'absolute', left: 0, right: 0, top: 320, textAlign: 'center', fontFamily: FMONO, fontSize: 110, color: C.white, letterSpacing: '0.02em', opacity: 1 - f, transform: `translateY(${-24 * f}px)`, whiteSpace: 'nowrap' }}>08:59</div>
          <div style={{ position: 'absolute', left: 0, right: 0, top: 320, textAlign: 'center', fontFamily: FMONO, fontSize: 110, color: C.orangeHi, letterSpacing: '0.02em', opacity: f, transform: `translateY(${24 * (1 - f)}px)`, whiteSpace: 'nowrap' }}>09:00</div>

          <div style={{ position: 'absolute', left: 0, right: 0, top: 500, display: 'flex', justifyContent: 'center' }}>
            <TriggerChip t={t} at={2.6} label="run started" />
          </div>
        </div>

        <div style={{ position: 'absolute', left: 64, top: 1256, width: 952, opacity: clamp((t - 3.0) / 0.4, 0, 1), fontFamily: FTEXT, fontSize: 27, fontWeight: 300, color: C.fg2, whiteSpace: 'nowrap' }}>
          09:00 on weekdays. <span style={{ color: C.white, fontWeight: 500 }}>A run starts.</span>
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
  const tag2E = clamp((t - 1.0) / 0.6, 0, 1);
  return (
    <div style={{ position: 'absolute', inset: 0, background: C.black, overflow: 'hidden' }}>
      <img src="assets/Ring_Orange.png" alt="" style={{ position: 'absolute', left: '50%', top: 470, width: 1180, height: 1180, transform: `translate(-50%,-50%) scale(${ringScale}) rotate(${ringRot}deg)`, opacity: 0.9, objectFit: 'contain' }} />
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(circle at 50% 24%, transparent 30%, rgba(10,9,8,0.55) 60%, #0A0908 82%)' }} />
      <div style={{ position: 'absolute', left: 0, right: 0, top: 1090, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 34 }}>
        <img src="assets/logo-wordmark-white.svg" alt="Aixle" style={{ width: 420, opacity: logoE, transform: `translateY(${(1 - Easing.easeOutCubic(logoE)) * 22}px)` }} />
        <div style={{ fontFamily: FDISP, fontWeight: 700, fontSize: 32, letterSpacing: '0.42em', color: C.orange, marginTop: -18, marginLeft: '0.42em', opacity: logoE }}>FLOW</div>
        <div style={{ maxWidth: 900, textAlign: 'center', fontFamily: FDISP, fontSize: 42, fontWeight: 400, letterSpacing: '-0.02em', color: C.white, lineHeight: 1.12, opacity: tagE, transform: `translateY(${(1 - Easing.easeOutCubic(tagE)) * 18}px)`, whiteSpace: 'nowrap' }}>
          Board. Slack. Webhook. Schedule.
        </div>
        <div style={{ maxWidth: 820, textAlign: 'center', fontFamily: FTEXT, fontSize: 27, fontWeight: 300, color: C.fg2, opacity: tag2E, transform: `translateY(${(1 - Easing.easeOutCubic(tag2E)) * 16}px)`, whiteSpace: 'nowrap' }}>
          Runs start where your work happens.
        </div>
        <div style={{ fontFamily: FMONO, fontSize: 22, color: C.fg2, opacity: tag2E, letterSpacing: '0.02em' }}>aixle.com</div>
      </div>
    </div>
  );
}

function TriggersAd() {
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
window.TriggersAd = TriggersAd;

function Movie() {
  const { Stage } = window;
  return React.createElement(Stage, { width: 1080, height: 1920, duration: 20, background: C.black, persistKey: 'aixle-triggers-v' },
    React.createElement(TriggersAd));
}
window.Movie = Movie;
