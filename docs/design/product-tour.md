# Getting started and the product tour

Built 2026-11-25 behind the `product_tour` release flag (task #51). The starter template it
relies on, `aixle/hello-flow`, is not yet in `AixleHQ/flow-templates`: until the catalog carries
it, tour A is hidden everywhere and only viewers get a tour.

After onboarding a new member used to land on an empty project list with nothing to say where to
start. Now they land on **Getting started**, and from there a click-through **product tour** shows
how Flow works on a real run: install a template, run its workflow, watch the run, find the result.

## Library: Driver.js

The tour draws a mask over the page with a cut-out around one element and a popover next to it.

| Option | Licence | Verdict |
|---|---|---|
| **Driver.js 1.x** | MIT | **Chosen.** Vanilla JS with no dependencies and no React peer, so React 19 is no concern. An SVG overlay with a cut-out, a popover styled with our own CSS, and a mode that keeps the highlighted element clickable while the rest of the page is blocked. Pinned at `^1.10.2`. |
| Shepherd.js | AGPL-3.0 or a paid licence | Rejected: Flow is Apache-2.0 and distributed for self-hosting. |
| Intro.js | AGPL-3.0 or a paid licence | Rejected for the same reason. |
| React Joyride | MIT | Lags on React 19, brings its own floater styling and its own route handling. |
| Hopscotch | — | Unmaintained. |
| Our own overlay on a Mantine `Popover` | — | More code to own: cut-out geometry, scroll and resize, portals over drawers. |

Driver.js draws **one step at a time** (`driver().highlight(...)`); the step order, the page
changes and what is remembered belong to our engine. The library sits behind a two-method
interface (`TourHighlighter`: `show`, `clear`) in `shared/lib/productTour/highlighter.ts`, so it
can be replaced, and tests drive the engine with a fake.

## What a member sees

**Landing.** `AuthConcern#app_home_path` is the one place every landing goes through (after
onboarding, after sign-in, after a step-up). With the flag on it returns Getting started while
`CompanyMembership#getting_started_pending?` holds: onboarding is complete and the member has
not finished the tour for their role. Finishing covers skipping.

**Getting started** (`GettingStarted/GettingStartedPage`, `company_getting_started_path`) is in no
menu and no sidebar. A member who can write sees four cards:

1. **Connect your agents** links to Profile; it reads "Connected ✓" once an agent is connected.
2. **Take the product tour** starts tour A; disabled with "Connect an agent first" until an agent
   is connected, and absent when Hello Flow is not in the catalog.
3. **Discover community templates** opens Templates.
4. **Build your own**: **Build with AI** posts to `getting_started/build_with_ai`, which opens AI
   Builder in the member's newest project or, with none, creates "New Project" (numbered when the
   name is taken in the company) first; **Set up Personal MCP** opens the Profile MCP tab.

A viewer sees only the tour card, always enabled, which starts tour B.

**User menu.** **Start product tour** sits after Send feedback while the flag is on. It starts the
tour for the member's role from its first step, restarting a running one. For tour A it is
disabled while no agent is connected or Hello Flow is not in the catalog, with the reason under
the label.

## Server side

| Piece | Where |
|---|---|
| Flag | `product_tour` in `config/feature_flags.yml` (`release`, `company`, `client: true`) |
| Finished tours | `company_memberships.product_tour_a_finished_at`, `product_tour_b_finished_at` |
| Backfill | members who finished onboarding before the tour existed count as having finished both tours, so turning the flag on sends no existing member to Getting started |
| Rules | `CompanyMembership#product_tour_variant` (viewer: `b`, anyone else: `a`), `#getting_started_pending?`, `#finish_product_tour!` |
| Getting started | `Web::Company::GettingStartedController#show`, `#build_with_ai` (the project-create rule: a viewer is refused) |
| Finishing | `PATCH company/:slug/product_tour` with `{ variant }`, `Web::Company::ProductToursController`; a viewer may, it is their own record |
| Run status | `GET …/workflow_runs/:id/status` → `{ id, state, finished }`, a project read like the run page |
| Shared prop | `currentUser.productTour`: `{ variant, aFinished, bFinished, helloFlowAvailable }` |
| Catalog check | `ProductTour.hello_flow_available?`, cached ten minutes because the user menu reads it on every page |

Storing the finish per membership answers "the tour is shown once, but roles differ per company"
the way onboarding does: a viewer in one company is still offered tour A in a company where they
can run things, and a viewer promoted to employee has not finished tour A, so Getting started comes
back for them with every card.

## The engine

`shared/lib/productTour/`, mounted once in `entrypoints/application.tsx` around the Inertia app:
the `withApp` tree is the only one that outlives page visits (layouts remount on each).

- `tours.ts` declares the steps: the Inertia page each one is on, its `data-tour` target, how it
  advances (`click`, `next`, `finish`), its copy, and what Next visits.
- `ProductTourProvider` follows the pages with `router.on('navigate')` (it sits above the page
  context, so `usePage` is not available) and takes the boot page from the page JSON. For each step
  it waits for the page, waits up to 5 s for `[data-tour=…]` with a `MutationObserver`, and has the
  highlighter draw it with **Skip tour** always there.
- A `click` step has no Next button: the highlighted element stays clickable, the rest is blocked,
  and the tour moves on when the click's page arrives (at once when the next step is on the same
  page, such as Run opening its drawer). The step it waits for is written to `sessionStorage` too,
  because the template page's Install is a plain link and loads a whole page.
- Progress (`variant`, step, the project and run it picked up) lives in `sessionStorage`, so a
  reload resumes and each tab is its own. The server only learns the finish.
- A missing target shows a centred popover with **End tour**, and **Skip this step** where the next
  step can be reached without the click, instead of hanging.
- Before a step that points into the sidebar, an `product-tour:expand-sidebar` window event makes
  `AppSidebar` expand itself and every group.

### Tour A

| Step | Page | Target | Advance |
|---|---|---|---|
| A1 | Projects | `nav-templates` (sidebar) | click |
| A2 | Templates | `template-card:aixle/hello-flow` | click |
| A3 | Template | `template-parts` | Next |
| A4 | Template | `template-install` | click |
| A5 | Install | `install-form`, click on `install-submit` | click |
| A6 | Set up checklist | `setup-checklist` | Next → project overview |
| A7 | Project overview | `sidebar-nav` | Next → Workflows |
| A8 | Workflows | `workflow-card` (first) | Next |
| A9 | Workflows | `workflow-run` (first) | click |
| A10 | Workflows (drawer) | `run-drawer-submit` | click |
| A11 | Run | `run-sessions` | Next |
| A12 | Run | `run-console` | Next |
| A13 | Run | `run-assets-tab` | Next |
| A14 | Board | `board-trigger-column` | Next |
| A15 | any | — | Finish |

Before A9 and A10 the engine checks that an agent is connected; without one it points to the agent
setup ("Connect an agent to run") with **Open profile**. At A13 it asks the run's status. Completed:
it opens the Assets tab, then the board. Failed or cancelled: "This run failed. Open Sessions &
Runs to see why", then the end. Still going: "It takes ~1–2 min. Meanwhile, let's look at the
board", then the board, while it polls the status every 10 s for up to 15 minutes; when the run
ends a toast says "Your first run finished" with **See the result**, which opens A13 on the run page
and then the end.

### Tour B (viewer)

Projects (`projects-list`) → the first project's board (`board`) → Sessions & Runs
(`sessions-list`) → "Ask an admin to give you edit access to run workflows". With no project, from
the projects page straight to the end.

## Where the build differs from the card

- **A6**: the installer always adds an "Activate trigger" item for Hello Flow's inactive column
  trigger, so the copy says "Hello Flow only has a trigger you can switch on later" instead of
  "nothing left here".
- **A13**: the run page has an Assets **tab**, not a block; the tour opens it.
- **A14**: template v1 cannot ship board cards (the format has no `board.cards`, the exporter leaves
  cards out), so A14 highlights the column bound to a trigger and the copy reads "Move a card into
  this column…". Adding cards to the template format (schema, validator, installer, flow-templates
  CI) was left out.
- **Menu entry**: a disabled Mantine menu item cannot show a tooltip (a disabled button swallows the
  pointer events), so the reason is written under the label.
- **A1** starts on the Projects page: starting a tour visits it first.

## Not in this repository

**Hello Flow** belongs in `AixleHQ/flow-templates` (`templates/aixle/hello-flow/`): a project
template with two steps, no secrets, integrations or repositories, one board column with a
`kind: column` trigger, and one install input (the member's role) for the recommended one-pager
"What Flow can automate for you", the only option that needs no internet access in the agent's
container. It reaches installations through the hourly catalog sync; until then
`helloFlowAvailable` is false and tour A stays hidden. A self-hosted installation with no access
to the template repository is in the same position.

## Risks

- A refactor that drops a `data-tour` attribute breaks the tour silently: `tours.test.ts` checks
  that every target and page a step names exists in the source.
- The run spends the member's own tokens; a quota error makes the first experience a failure. The
  tour does not wait on success (see A13), and Hello Flow must stay small.
- The Run drawer is in a Mantine portal under Driver's overlay. The highlighted button stays
  clickable through the cut-out; the rest of the drawer is dimmed with the page.
