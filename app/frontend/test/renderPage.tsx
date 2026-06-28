import { MantineProvider } from '@mantine/core';
import { ModalsProvider } from '@mantine/modals';
import { Notifications } from '@mantine/notifications';
import { render } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { ReactElement, ReactNode } from 'react';

import { cssVariablesResolver, mantineTheme } from 'shared/theme/mantineTheme';

import { buildSharedProps } from './factories/sharedProps';
import { inertiaState, makeFormStub } from './inertiaMock';

/**
 * Render a page/component inside the app's real provider tree (minus Sentry + Inertia boot).
 * `env="test"` disables Mantine transitions to avoid timing flake.
 * Pass `props` to seed usePage().props and `form` to seed useForm().
 */
export function renderPage<TProps extends Record<string, unknown>>(
  ui: ReactElement,
  opts: { props?: TProps; form?: ReturnType<typeof makeFormStub> } = {},
) {
  inertiaState.pageProps = opts.props ?? {};
  // Reset to null so a prior test's pinned form never leaks; when null, the useForm() mock seeds a
  // fresh stub from the component's own initial data.
  inertiaState.form = opts.form ?? null;
  return render(ui, {
    wrapper: ({ children }: { children: ReactNode }) => (
      <MantineProvider
        theme={mantineTheme}
        defaultColorScheme="dark"
        cssVariablesResolver={cssVariablesResolver}
        env="test"
      >
        <ModalsProvider>
          <Notifications />
          {children}
        </ModalsProvider>
      </MantineProvider>
    ),
  });
}

/**
 * Like renderPage(), but pre-seeds the SharedProps every AuthLayout/ProjectLayout reads
 * (currentUser/flash/projects/permissions/settings). Page-specific props are merged on top, so a
 * page test only declares what it actually asserts. Use for any page rendered inside a layout.
 */
export function renderAuthedPage<TProps extends Record<string, unknown>>(
  ui: ReactElement,
  opts: { props?: Partial<TProps>; form?: ReturnType<typeof makeFormStub> } = {},
) {
  return renderPage(ui, { ...opts, props: { ...buildSharedProps(), ...opts.props } });
}

export { userEvent, makeFormStub, buildSharedProps };
export * from '@testing-library/react';
