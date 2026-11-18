/**
 * Every element the product tour points at. Markup marks an element with `tourTarget(...)`, and
 * the tour finds it by the same name, so renaming or removing a target is a type error on both
 * sides. `targets.test.ts` fails when a name here is no longer put on any element.
 */
export const TOUR_TARGETS = [
  'sidebar-templates',
  'template-card',
  'template-contents',
  'template-install',
  'install-submit',
  'setup-checklist',
  'project-nav-work',
  'workflow-card',
  'workflow-run',
  'run-drawer-submit',
  'run-sessions',
  'run-console',
  'run-assets-tab',
  'board',
  'project-card',
] as const;

export type TourTarget = (typeof TOUR_TARGETS)[number];

export const tourTarget = (name: TourTarget) => ({ 'data-tour': name });

export const tourSelector = (name: TourTarget) => `[data-tour="${name}"]`;
