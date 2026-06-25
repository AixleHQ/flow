import { MantineProvider } from '@mantine/core';
import { ModalsProvider } from '@mantine/modals';
import { Notifications } from '@mantine/notifications';
import { render } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { ReactElement, ReactNode } from 'react';

import { cssVariablesResolver, mantineTheme } from 'shared/theme/mantineTheme';

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
  if (opts.form) inertiaState.form = opts.form;
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

export { userEvent, makeFormStub };
export * from '@testing-library/react';
