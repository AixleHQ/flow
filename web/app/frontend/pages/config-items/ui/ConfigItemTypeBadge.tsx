import { Chip } from '@mui/material';
import type { FC } from 'react';

import type { ConfigItemType } from '../lib/types';

interface ConfigItemTypeBadgeProps {
  type: ConfigItemType;
}

const ConfigItemTypeBadge: FC<ConfigItemTypeBadgeProps> = ({ type }) => {
  const isSecret = type === 'secret';

  return (
    <Chip
      label={isSecret ? 'Secret' : 'Variable'}
      size="small"
      sx={{
        fontSize: 11,
        height: 24,
        backgroundColor: isSecret ? 'rgba(239, 68, 68, 0.15)' : 'rgba(59, 130, 246, 0.15)',
        color: isSecret ? '#F87171' : '#60A5FA',
        border: `1px solid ${isSecret ? 'rgba(239, 68, 68, 0.3)' : 'rgba(59, 130, 246, 0.3)'}`,
      }}
    />
  );
};

export { ConfigItemTypeBadge };
