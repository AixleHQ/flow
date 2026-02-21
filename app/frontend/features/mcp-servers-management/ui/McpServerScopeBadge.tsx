import { Chip, type ChipProps } from '@mui/material';
import type { FC } from 'react';

type ScopeIndicator = 'internal' | 'company' | 'project' | 'overrides_company';

interface McpServerScopeBadgeProps {
  scopeIndicator: ScopeIndicator;
}

const scopeConfig: Record<ScopeIndicator, { label: string; color: ChipProps['color'] }> = {
  internal: { label: 'Internal', color: 'default' },
  company: { label: 'Company', color: 'primary' },
  project: { label: 'Project', color: 'secondary' },
  overrides_company: { label: 'Overrides Company', color: 'warning' },
};

export const McpServerScopeBadge: FC<McpServerScopeBadgeProps> = ({ scopeIndicator }) => {
  const config = scopeConfig[scopeIndicator] ?? scopeConfig.company;

  return <Chip label={config.label} color={config.color} size="small" />;
};
