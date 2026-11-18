import { createRoot, type Root } from 'react-dom/client';

import Dashboard from 'pages/Admin/Dashboard/Dashboard';
import type { DashboardData } from 'pages/Admin/Dashboard/types';

// Mounted on an Administrate page (or on /dashboard, in the same shell), not
// inside the Inertia app: no MantineProvider and none of Mantine's global CSS,
// which would restyle Administrate's own chrome.
// The --app-* tokens it draws on come from the admin skin (entrypoints/admin.css).
//
// Administrate navigates with Turbo, which does not run this module again on a
// later visit, so the island mounts on every turbo:load, and unmounts before
// Turbo caches the page so a restored snapshot is not a dead copy of it.
let root: Root | null = null;

function mount() {
  const element = document.getElementById('admin-dashboard');
  const { report, base, companyRecords } = element?.dataset ?? {};
  if (!element || !report || !base || root) return;

  root = createRoot(element);
  root.render(<Dashboard data={JSON.parse(report) as DashboardData} paths={{ base, companyRecords }} />);
}

document.addEventListener('turbo:load', mount);
document.addEventListener('turbo:before-cache', () => {
  root?.unmount();
  root = null;
});
mount();
