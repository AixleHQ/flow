import { Breadcrumbs, Text, UnstyledButton } from '@mantine/core';
import { IconChevronRight, IconHome } from '@tabler/icons-react';

interface Crumb {
  path: string;
  label: string;
}

interface AssetsBreadcrumbsProps {
  currentPath: string;
  onNavigate: (path: string) => void;
}

export function AssetsBreadcrumbs({ currentPath, onNavigate }: AssetsBreadcrumbsProps) {
  const parts = currentPath ? currentPath.split('/') : [];
  let acc = '';
  const crumbs: Crumb[] = [
    { path: '', label: 'Assets' },
    ...parts.map((p) => {
      acc = acc ? `${acc}/${p}` : p;
      return { path: acc, label: p };
    }),
  ];

  return (
    <Breadcrumbs
      separator={<IconChevronRight size={13} style={{ opacity: 0.5, flexShrink: 0 }} />}
      mb={14}
      styles={{ root: { rowGap: 4 }, breadcrumb: { minWidth: 0 } }}
    >
      {crumbs.map((crumb, i) => {
        const isCurrent = i === crumbs.length - 1;
        return (
          // Mantine's Breadcrumbs clones each child and injects its own style/className via
          // cloneElement, which replaces rather than merges — a style prop set directly on this
          // button is silently dropped (only `styles.breadcrumb` survives). The flex layout has
          // to live on an inner wrapper instead, where our own render controls the props.
          <UnstyledButton
            key={crumb.path || 'root'}
            onClick={() => onNavigate(crumb.path)}
            disabled={isCurrent}
            title={crumb.label}
          >
            <span
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 5,
                minWidth: 0,
                cursor: isCurrent ? 'default' : 'pointer',
                padding: '2px 4px',
                borderRadius: 5,
              }}
            >
              {i === 0 && <IconHome size={13} style={{ flexShrink: 0, opacity: 0.7 }} />}
              <Text
                size="sm"
                fw={isCurrent ? 600 : 400}
                c={isCurrent ? 'var(--app-text-primary)' : 'var(--app-text-secondary)'}
                truncate="end"
                maw={220}
              >
                {crumb.label}
              </Text>
            </span>
          </UnstyledButton>
        );
      })}
    </Breadcrumbs>
  );
}
