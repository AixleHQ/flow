import { Badge } from '@mantine/core';

import { KIND_COLORS, KIND_LABELS, type TemplateKind } from '../types';

export function KindBadge({ kind }: { kind: TemplateKind }) {
  return (
    <Badge color={KIND_COLORS[kind]} variant="light" radius="sm" size="sm" ff="var(--app-font-mono-label)">
      {KIND_LABELS[kind]}
    </Badge>
  );
}
