import { DEFAULT_THEME, mergeMantineTheme } from '@mantine/core';
import { createRoot } from 'react-dom/client';

import TenantUsageReport from 'pages/Admin/TenantUsage/TenantUsageReport';
import type { TenantUsageData } from 'pages/Admin/TenantUsage/types';
import { cssVariablesResolver, mantineTheme } from 'shared/theme/mantineTheme';

// Mounted on an Administrate page, not inside the Inertia app: no MantineProvider
// and none of Mantine's global CSS, which would restyle Administrate's own chrome.
// The --app-* tokens are still the theme's, light scheme to match Administrate,
// set on the mount point only.
const mount = document.getElementById('tenant-usage-report');

if (mount?.dataset.report) {
  const { variables, light } = cssVariablesResolver(mergeMantineTheme(DEFAULT_THEME, mantineTheme));
  for (const [name, value] of Object.entries({ ...variables, ...light })) mount.style.setProperty(name, value);

  const data = JSON.parse(mount.dataset.report) as TenantUsageData;
  createRoot(mount).render(<TenantUsageReport data={data} />);
}
