import { Head } from '@inertiajs/react';
import type { ReactNode } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

/**
 * Type-safe persistent layout assignment for Inertia page components.
 * Centralizes the unavoidable `any` cast required by Inertia's layout API.
 */
export function setPageLayout(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  page: (props: any) => ReactNode,
  layout: ((props: { children: ReactNode }) => ReactNode) | ((props: { children: ReactNode }) => ReactNode)[],
) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (page as any).layout = layout;
}

export interface ProjectLayoutProps {
  projectId: number;
  projectName: string;
  currentTab: string;
  title?: string;
  children: ReactNode;
}

/**
 * Wrapper component for backward compatibility — still used by pages that
 * haven't migrated to persistent layout yet.
 */
export const ProjectLayout = ({ projectId, projectName, currentTab, title, children }: ProjectLayoutProps) => (
  <AuthLayout projectId={String(projectId)} currentTab={currentTab}>
    <Head title={title ? `${title} — ${projectName}` : projectName} />
    {children}
  </AuthLayout>
);

/**
 * Persistent layout for Inertia v3: pass a component reference (not a render
 * function) so Inertia uses `createElement` and React preserves the instance
 * across navigations — sidebar, header, and scroll position stay mounted.
 */
export const persistentProjectLayout = AuthLayout;

function AuthLayoutNoPadding({ children }: { children: ReactNode }) {
  return <AuthLayout noPadding>{children}</AuthLayout>;
}

export const persistentProjectLayoutNoPadding = AuthLayoutNoPadding;
