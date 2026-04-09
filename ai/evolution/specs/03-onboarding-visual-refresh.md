# Onboarding Page — Visual Refresh Specification

> **Scenario:** `ai/evolution/scenarios/03-onboarding-visual-refresh.md`
> **Created:** 2026-04-03
> **Risk:** Low (frontend-only, no API changes)

---

## Change Summary

Visual update to Onboarding: gradient background + card animation (consistency with Login S-02), company branding (logo + name), auto-save with debounce on Step 1/2, 4 agents (+ Gemini CLI), agent cards with color bars and hover, inline validation warnings, Step 4 redesign with agent summary cards, step transition animation, migration to SharedProps types.

---

## Before

```
┌──────────────────────────────────────────────────┐
│  (flat #0D0D0D background)                       │
│                                                  │
│  ┌─────────────────────────────────────────┐     │
│  │  🚀 Welcome to the Platform             │     │
│  │  "Let's get you set up..."              │     │
│  │                                          │     │
│  │  ○─────○─────○─────○  (Stepper)         │     │
│  │                                          │     │
│  │  ┌─────────────────────┐                │     │
│  │  │  Tell us about...   │                │     │
│  │  │  [Position ▼]       │ ← no auto-save │     │
│  │  │  [Language ▼]       │ ← no validation│     │
│  │  │         [Continue]  │                │     │
│  │  └─────────────────────┘ ← appears      │     │
│  │                            instant       │     │
│  └─────────────────────────────────────────┘     │
│   (no company branding, no gradient, 3 agents)   │
└──────────────────────────────────────────────────┘
```

---

## After

```
┌──────────────────────────────────────────────────┐
│  (radial gradient: dark-7 center → dark-9 edges) │
│                                                  │
│  ┌─────────────────────────────────────────┐     │
│  │  [Company Logo]                          │ ← fadeSlideUp
│  │  🚀 Welcome to Acme Corp!               │   300ms
│  │  "Let's set up your profile..."          │
│  │                                          │
│  │  ○─────○─────○─────○  (Stepper)         │
│  │                                          │
│  │  ┌─────────────────────────┐             │ ← step fade
│  │  │  Tell us about...       │             │
│  │  │  [Position ▼]           │ ← auto-save │
│  │  │  [Language ▼]           │ ← debounce  │
│  │  │  ⚠ Fill required fields │ ← warning  │
│  │  │            [Continue]   │             │
│  │  └─────────────────────────┘             │
│  └─────────────────────────────────────────┘     │
│   (company name, gradient, 4 agents, animated)   │
└──────────────────────────────────────────────────┘
```

---

## Components

### 1. `OnboardingPage.module.css` — New file

```css
/* ── Background ── */
.pageBackground {
  background: radial-gradient(
    ellipse at 50% 0%,
    var(--mantine-color-dark-7) 0%,
    var(--mantine-color-dark-9) 70%
  );
}

/* ── Welcome card ── */
@keyframes fadeSlideUp {
  from { opacity: 0; transform: translateY(16px); }
  to { opacity: 1; transform: translateY(0); }
}

.welcomeCard {
  animation: fadeSlideUp 0.3s ease-out both;
}

@media (prefers-reduced-motion: reduce) {
  .welcomeCard { animation: none; }
  .stepContent { animation: none; }
}

/* ── Step content transition ── */
.stepContent {
  animation: fadeSlideUp 0.2s ease-out both;
}

/* ── Agent cards (Step 2) ── */
.agentCard {
  cursor: pointer;
  transition: border-color 150ms ease, background-color 150ms ease, transform 150ms ease;
}

.agentCard:hover {
  transform: translateY(-2px);
}

/* ── Agent summary cards (Step 4) ── */
.summaryCard {
  transition: transform 150ms ease;
}

/* ── Footer subtitle ── */
.subtitle {
  font-family: var(--app-font-body, 'Inter', sans-serif);
}
```

### 2. `OnboardingPage.tsx` — Rewrite

**2a. Types: use SharedProps**

Remove local `CurrentUser` and `SharedProps` interfaces. Import from `shared/ui-inertia/types`:

```typescript
import type { SharedProps, SharedUser, SharedCompany } from 'shared/ui-inertia';
```

Access:
```typescript
const { current_user } = usePage<SharedProps>().props;
const company = current_user?.company;
```

**2b. Company branding welcome section**

```tsx
<Center mb="xl">
  <Stack align="center" gap={4}>
    {company?.logo_url && (
      <img src={company.logo_url} alt={company.name} style={{ height: 48, marginBottom: 8 }} />
    )}
    <ThemeIcon size="xl" radius="xl" variant="gradient" gradient={{ from: 'blue', to: 'cyan' }}>
      <IconRocket size={28} />
    </ThemeIcon>
    <Text size="xl" fw={700}>Welcome to {company?.name ?? 'the Platform'}!</Text>
    <Text size="sm" c="dimmed">Let's set up your profile and AI agents to get started</Text>
  </Stack>
</Center>
```

**2c. Gradient background**

```tsx
<Box maw={800} mx="auto" py={60} px="md" className={classes.pageBackground} mih="100vh">
```

**2d. Available agents: add Gemini CLI**

```typescript
const AVAILABLE_AGENTS = [
  { type: 'claude_code', name: 'Claude Code', description: "Anthropic's AI coding assistant with deep reasoning capabilities" },
  { type: 'cursor_cli', name: 'Cursor CLI', description: 'AI-powered code editor with context-aware suggestions' },
  { type: 'codex', name: 'OpenAI Codex', description: "OpenAI's code generation model optimized for multiple languages" },
  { type: 'gemini_cli', name: 'Gemini CLI', description: "Google's multimodal AI assistant for code generation and analysis" },
];
```

**2e. Auto-save with debounce (Step 1 + Step 2)**

```typescript
const autoSaveRef = useRef<ReturnType<typeof setTimeout>>();

const autoSave = useCallback((data: Record<string, unknown>) => {
  if (autoSaveRef.current) clearTimeout(autoSaveRef.current);
  autoSaveRef.current = setTimeout(() => {
    router.patch('/onboarding', { onboarding: data }, { preserveScroll: true });
  }, 300);
}, []);
```

Step 1 field changes trigger `autoSave({ position, preferred_agent_language: language })`.
Step 2 selection changes trigger `autoSave({ selected_agents: newAgents })`.

**2f. Inline validation**

```typescript
const [validationWarning, setValidationWarning] = useState<string | null>(null);
```

Step 1: if Continue clicked without both fields → `setValidationWarning('Please fill in all required fields to continue')`.
Step 2: if Continue clicked with 0 agents → `setValidationWarning('Select at least one agent to continue')`.

Shown as `<Text size="sm" c="yellow">⚠ {validationWarning}</Text>` above the button row.

**2g. Agent cards with color bars (Step 2)**

```tsx
<Card
  key={agent.type}
  withBorder
  p="md"
  className={classes.agentCard}
  style={{
    borderLeft: `4px solid ${AGENT_COLORS[agent.type] ?? '#666'}`,
    borderColor: selected ? 'var(--mantine-color-blue-6)' : undefined,
    backgroundColor: selected ? 'var(--mantine-color-blue-light)' : undefined,
  }}
  onClick={() => toggleAgent(agent.type)}
>
```

**2h. Step 4: agent summary cards**

Replace inline badges with summary cards:

```tsx
{selectedAgents.map((a) => {
  const agent = AVAILABLE_AGENTS.find((ag) => ag.type === a);
  const isAuth = current_user.configured_agents.includes(a);
  return (
    <Card key={a} withBorder p="sm" className={classes.summaryCard}
      style={{ borderLeft: `4px solid ${AGENT_COLORS[a] ?? '#666'}` }}>
      <Group justify="space-between">
        <Text size="sm" fw={500}>{agent?.name ?? a}</Text>
        <Badge size="sm" color={isAuth ? 'green' : 'yellow'} variant="filled">
          {isAuth ? '✓ Authenticated' : '⚠ Not authenticated'}
        </Badge>
      </Group>
    </Card>
  );
})}
```

**2i. Step transition animation**

Wrap each step content in:
```tsx
<Box key={`step-${activeStep}`} className={classes.stepContent}>
  {/* step content */}
</Box>
```

The `key` change forces re-mount → animation replays.

---

## Responsive Behavior

| Breakpoint | Behavior |
|-----------|----------|
| Desktop (>768px) | Max-width 800px centered, agent grid 2 cols |
| Tablet (480-768px) | Agent grid 2 cols, auth split stays |
| Mobile (<480px) | Agent grid 1 col, auth panel stacks vertically |

---

## Files Changed

| File | Change Type |
|------|-------------|
| `pages-inertia/Onboarding/OnboardingPage.tsx` | Major rewrite |
| `pages-inertia/Onboarding/OnboardingPage.module.css` | New file |

---

## Acceptance Criteria

| # | Criterion | Test |
|---|-----------|------|
| 1 | Company name in welcome | See "Welcome to {companyName}!" |
| 2 | Company logo displayed (if present) | Logo image above welcome text |
| 3 | Gradient background | Radial gradient visible, not flat dark |
| 4 | Card fadeSlideUp animation | Card fades in and slides up on load |
| 5 | Auto-save Step 1 | Change Position → network PATCH after 300ms |
| 6 | Auto-save Step 2 | Toggle agent → network PATCH after 300ms |
| 7 | 4 agents listed | Claude Code, Cursor CLI, Codex, Gemini CLI |
| 8 | Agent cards with color bars | Left border = agent theme color |
| 9 | Validation Step 1 | Click Continue without fields → yellow warning |
| 10 | Validation Step 2 | Click Continue without agents → yellow warning |
| 11 | Step 4 agent summary cards | Cards with color bars and auth badges |
| 12 | Step transition animation | Fade on step change |
| 13 | SharedProps types used | No local type duplication |
| 14 | Reduced motion respected | No animation with prefers-reduced-motion |

---

## Edge Cases

| Case | Expected |
|------|----------|
| Company without logo | Logo not shown, company name still displayed |
| Company without name | Fallback to "the Platform" |
| User refreshes mid-step | Backend state preserved, correct step shown |
| 0 agents selected on Step 3 | Step 3 shows empty agent list |
| Auto-save network error | Silent fail, data saved on Continue click |
| Very long company name | Text wraps naturally |
| prefers-reduced-motion | All animations disabled |
