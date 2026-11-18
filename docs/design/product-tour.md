# Product tour

Flow Dev #51 (GitHub palad-ai/palad-app#374). The scenario, its copy and the product decisions
are in the task's `product-tour-scenario.md` (2026-11-12); this document records the library
choice, how the tour is built, and how it is kept in step with the UI.

Status: first iteration behind the `product_tour` flag (default off). Chapter A (first run) and
chapter B (viewer) work end to end; the gaps are listed under [Not done yet](#not-done-yet).

## Library: driver.js

| | driver.js | react-joyride | Shepherd.js | Intro.js | Hopscotch |
|---|---|---|---|---|---|
| License | MIT | MIT | **AGPL-3.0** (commercial licence sold separately) | **AGPL-3.0** / commercial | Apache-2.0 |
| Framework | none (vanilla, works next to React 19) | React (peer `react` 16.8–19) | vanilla + wrappers | vanilla | vanilla |
| Size (min+gz) | ~5 KB, no dependencies | ~30 KB with floater/popper deps | ~25 KB with floating-ui | ~10 KB | ~8 KB |
| Step UI | plain DOM, styled by our CSS; `onPopoverRender` for extra content | React components | HTML templates | CSS | CSS |
| Maintenance | active (1.10–1.14 in Oct–Nov 2026, original author) | active | active | slow | **abandoned since 2017** |

**Chosen: driver.js 1.10.2**, pinned exactly (the newest release older than a month at the time
of the choice; 1.11–1.14 came out within the past ten days).

Why:

- **License.** Flow is Apache-2.0 and shipped as self-hosted open source. Shepherd.js and
  Intro.js are AGPL: linking them would either relicense the frontend or need a paid licence.
  That rules them out before any technical comparison.
- **It does exactly what the scenario asks** — a dimmed overlay with a cut-out around one
  element, a popover next to it, the highlighted element still clickable while the rest of the
  page is not (`highlight()` with the default `disableActiveInteraction: false`). Nothing more to
  remove or fight.
- **No React coupling.** The tour crosses Inertia visits *and* full page loads (Install is a
  plain link). react-joyride keeps its state in a React tree, which a full load throws away; we
  would end up writing the same cross-page state as with driver.js, plus a heavier dependency.
- **Styling.** The popover is plain DOM with stable class names, so it takes the app's own CSS
  variables (`productTour.css`) and follows the light/dark theme with no theme bridge.

What we take on: driver.js runs steps on one page; going from page to page is ours (below).

## How it is built

```
app/frontend/shared/tour/
  targets.ts        the closed list of element names a step may point at; tourTarget() marks markup
  steps.ts          the scenario as data: page, target, copy, how the step advances, where Next goes
  resolveStep.ts    which step belongs on the current page (pure, unit-tested)
  tourStore.ts      tour position (sessionStorage) and the answer to the offer (localStorage, per user)
  ProductTour.tsx   mounted once in AuthLayout: the A0 offer, then one driver.js highlight per step
  productTour.css   the popover in the app's colours
```

- **Targets are named, not selected.** Markup says `{...tourTarget('workflow-run')}`, which
  renders `data-tour="workflow-run"`. Steps never use CSS classes, text or DOM structure, so a
  restyle, a renamed label or a moved wrapper does not break a step.
- **A step belongs to a page** (`page: RegExp` on the path). On every visit `ProductTour`
  shows the current step if the page matches, or waits — the person may take a detour and come
  back. It moves on by one step at most when the page already belongs to the next step (the
  install landed on the project rather than its checklist); it never jumps further, so wandering
  to the board does not skip the run.
- **Advancing.** `click` steps move on when the highlighted element is clicked, and the click
  goes through (navigation, opening the Run drawer). `next` steps move on with the popover's
  button and may open the next page (`goTo`). If a target does not appear within 6 s the popover
  is shown in the middle of the screen with a Next button, so nobody is ever stuck.
- **Who sees what.** `permissions.canWrite === false` gets chapter B. Without a connected agent
  (`currentUser.agentCredentials` empty — the "Skip for now" case, scenario risk 2) the Run steps
  are replaced by "Connect an agent first", which sends the person to My Profile.
- **Starting it.** The offer modal (A0) on Projects after onboarding: *Yes* starts, *Not now*
  brings it back on a later visit and stops after the second, *Don't show again* or the close
  button stops it. *Start product tour* in the user menu starts it any time.
  `?tour=first-run` / `?tour=viewer` starts a chapter directly, for QA.

## Risks when the design changes

| Change | What happens to the tour | Caught by |
|---|---|---|
| An element is restyled, its text or icon changes, it moves on the same page | Nothing: the step finds it by `data-tour` | — |
| A component is rewritten and the `tourTarget(...)` spread is dropped | The step falls back to a centred popover: the tour still works, but points at nothing | `targets.test.ts` fails: every name in `TOUR_TARGETS` must be marked somewhere in the app |
| A target name is renamed or removed in markup only | Same as above | `tourTarget()` takes only names from `TOUR_TARGETS`, so a typo is a type error; a removal fails `targets.test.ts` |
| A page moves to another URL | The step never matches; the tour waits on a page it will never see | Not caught automatically yet — the system test in [Not done yet](#not-done-yet) closes this |
| The flow itself changes (Install no longer goes through the checklist, Run no longer opens a drawer) | Steps describe a path that no longer exists | Not caught: a product change, reviewed with the scenario |
| An element is hidden by state (collapsed sidebar group, a run with no live console) | Centred popover; `optionalTarget` marks the ones expected to be absent sometimes | — |
| Copy describes the old UI ("in the Triggers tab") | Wrong text, nothing breaks | Not caught: copy review |
| A modal, drawer or sticky header covers the target | Highlight under another layer | Manual check |

## Keeping the design and the tour in step

1. **One source for copy.** The step text lives only in `steps.ts`, keyed by the scenario's
   step ids (A1…A15, B1…B4). A copy change edits that file and the scenario together.
2. **Mark, don't select.** New targets are added to `TOUR_TARGETS` and put on the element with
   `tourTarget()`. Never point a step at a class, a label or `nth-child`.
3. **The design file carries the targets too.** In Figma, frames that a step points at get the
   step id in the layer name (`[tour A9] Run`). A designer moving or removing such a layer knows a
   step depends on it; a developer implementing a design sees which `tourTarget()` to keep.
4. **A PR that touches a page with a `tourTarget(...)`** checks the tour on that page
   (`?tour=first-run`). Proposed, not set up yet: a PR template line and a CODEOWNERS entry for
   `shared/tour/`, so the reviewer sees it.
5. **Tests guard the wiring, not the pixels.** `targets.test.ts` (every target is marked, every
   target is used), `resolveStep.test.ts` (page matching, the agent branch). A system test that
   walks chapter A end to end is the next guard to add — it catches moved pages and flow changes.
6. **Version the tour.** When a change makes the old walk-through wrong, bump the chapter (keep
   the stored answer per chapter version) so people who finished the old tour are offered the new
   one once. Not needed yet.

## Demo on a local machine

```bash
docker compose up -d
docker compose exec -T web bin/rails runner \
  'FeatureFlags::Admin.set_global(:product_tour, true, actor: User.find_by(email: "admin@example.com"), reason: "local tour demo")'
```

Then sign in and open `http://localhost:4000/company/projects?tour=first-run` (or use *Start
product tour* in the menu under your name). The offer modal (A0) appears on Projects for a user
who has not answered it; to see it again clear `aixle:product-tour-offer:<user id>` in the
browser's localStorage. Until Hello Flow is in the catalog, step A2 points at the first template
card — pick a template that needs no secrets so that its run works.

## Not done yet

- **Hello Flow template** (scenario section 2, the main blocker). It lives in
  `AixleHQ/flow-templates`; until it ships the tour is not worth switching on in production.
- **The offer answer is per browser** (localStorage), not per user as decided (scenario
  decision 3). Moving it to the server is a `users.product_tour` jsonb column, a profile endpoint
  and a shared prop; it also enables the per-chapter memory from risk 5.
- **Waiting for the run (A13).** The tour does not wait for the run to finish or show the
  "Your first run finished" toast; A13 says the result comes in a minute or two and moves on.
- **System test** walking chapter A with the Capybara stack.
- **Self-hosted without catalog access** (risk 6): chapter A should be hidden when the catalog is
  empty.
