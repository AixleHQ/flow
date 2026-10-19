import { createRoot } from 'react-dom/client';

import Dashboard from 'pages/Admin/Dashboard/Dashboard';
import type { DashboardData } from 'pages/Admin/Dashboard/types';

// Mounted on an Administrate page, not inside the Inertia app: no MantineProvider
// and none of Mantine's global CSS, which would restyle Administrate's own chrome.
// The --app-* tokens it draws on come from the admin skin (entrypoints/admin.css).
const mount = document.getElementById('admin-dashboard');

if (mount?.dataset.report) {
  const data = JSON.parse(mount.dataset.report) as DashboardData;
  createRoot(mount).render(<Dashboard data={data} />);
}
