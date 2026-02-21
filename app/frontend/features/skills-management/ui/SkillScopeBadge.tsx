import { Chip } from '@mui/material';
import type { FC } from 'react';

import type { ScopeIndicator } from '../lib/types';

interface SkillScopeBadgeProps {
  indicator: ScopeIndicator;
}

const scopeLabels: Record<ScopeIndicator, string> = {
  internal: 'Internal',
  company: 'Company',
  project: 'Project',
  overrides_company: 'Overrides Company',
};

const scopeStyles: Record<ScopeIndicator, { bg: string; color: string; border: string }> = {
  internal: {
    bg: 'rgba(113, 113, 122, 0.15)',
    color: '#A1A1AA',
    border: 'rgba(113, 113, 122, 0.3)',
  },
  company: {
    bg: 'rgba(59, 130, 246, 0.15)',
    color: '#60A5FA',
    border: 'rgba(59, 130, 246, 0.3)',
  },
  project: {
    bg: 'rgba(34, 197, 94, 0.15)',
    color: '#4ADE80',
    border: 'rgba(34, 197, 94, 0.3)',
  },
  overrides_company: {
    bg: 'rgba(245, 158, 11, 0.15)',
    color: '#FBBF24',
    border: 'rgba(245, 158, 11, 0.3)',
  },
};

const SkillScopeBadge: FC<SkillScopeBadgeProps> = ({ indicator }) => {
  const style = scopeStyles[indicator];

  return (
    <Chip
      label={scopeLabels[indicator]}
      size="small"
      sx={{
        fontSize: 11,
        height: 24,
        backgroundColor: style.bg,
        color: style.color,
        border: `1px solid ${style.border}`,
      }}
    />
  );
};

export { SkillScopeBadge };
