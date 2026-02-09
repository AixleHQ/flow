import { Chip } from '@mui/material';
import type { FC } from 'react';

import type { SkillKind } from '../lib/types';

interface SkillKindBadgeProps {
  kind: SkillKind;
}

const kindLabels: Record<SkillKind, string> = {
  internal: 'Internal',
  custom: 'Custom',
};

const kindStyles: Record<SkillKind, { bg: string; color: string; border: string }> = {
  internal: {
    bg: 'rgba(113, 113, 122, 0.15)',
    color: '#A1A1AA',
    border: 'rgba(113, 113, 122, 0.3)',
  },
  custom: {
    bg: 'rgba(139, 92, 246, 0.15)',
    color: '#A78BFA',
    border: 'rgba(139, 92, 246, 0.3)',
  },
};

const SkillKindBadge: FC<SkillKindBadgeProps> = ({ kind }) => {
  const style = kindStyles[kind];

  return (
    <Chip
      label={kindLabels[kind]}
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

export { SkillKindBadge };
