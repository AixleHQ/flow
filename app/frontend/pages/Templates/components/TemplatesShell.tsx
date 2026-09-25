import { usePage } from '@inertiajs/react';
import type { ReactNode } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';
import { PublicLayout } from 'layouts/PublicLayout';

/** The catalog is public: guests get the public shell, members the app shell. */
export function TemplatesShell({ children }: { children: ReactNode }) {
  const { currentUser } = usePage().props as { currentUser?: unknown };
  return currentUser ? <AuthLayout>{children}</AuthLayout> : <PublicLayout>{children}</PublicLayout>;
}
