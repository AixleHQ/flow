import { Link } from '@inertiajs/react';
import { Drawer } from '@mantine/core';
import { useEffect, useState, type CSSProperties, type ReactNode } from 'react';

import { DOCS_SECTIONS, type DocsSection } from '../data/sections';
import classes from '../DocsPage.module.css';

import { DocsNavBar } from './DocsNavBar';
import { DocsSearchModal } from './DocsSearchModal';
import { DocsSidebar } from './DocsSidebar';

interface Props {
  active: DocsSection;
  /** The docs page being read, highlighted in the mobile drawer's page list. */
  currentSlug?: string;
  children: ReactNode;
}

const THEME = {
  '--mantine-color-dark-0': 'var(--app-text-primary)',
  '--mantine-color-dark-1': 'var(--app-text-secondary)',
  '--mantine-color-dark-2': 'var(--app-text-tertiary)',
  '--mantine-color-dark-3': 'var(--app-border-strong)',
  '--mantine-color-dark-4': 'var(--app-border-default)',
  '--mantine-color-dark-5': 'var(--app-bg-elevated)',
  '--mantine-color-dark-6': 'var(--app-bg-elevated)',
  '--mantine-color-dark-7': 'var(--app-bg-paper)',
  '--mantine-color-dark-8': 'var(--app-bg-default)',
  '--mantine-color-dark-9': 'var(--app-bg-deep)',
  '--mantine-color-blue-0': 'rgba(224,88,46,0.06)',
  '--mantine-color-blue-1': 'rgba(224,88,46,0.10)',
  '--mantine-color-blue-2': 'rgba(224,88,46,0.18)',
  '--mantine-color-blue-3': 'rgba(224,88,46,0.28)',
  '--mantine-color-blue-4': 'var(--mantine-color-brand-4)',
  '--mantine-color-blue-5': 'var(--app-primary)',
  '--mantine-color-blue-6': 'var(--mantine-color-brand-6)',
  '--mantine-color-blue-7': 'var(--mantine-color-brand-7)',
  '--mantine-color-blue-8': 'var(--mantine-color-brand-8)',
  '--mantine-color-blue-9': 'var(--mantine-color-brand-9)',
  // Callouts read from the app's status tokens, so they follow the
  // color scheme instead of being pinned to one dark-only set.
  '--callout-info-bg': 'var(--app-info-bg)',
  '--callout-info-border': 'var(--app-info-border)',
  '--callout-info-icon': 'var(--app-info-fg)',
  '--callout-info-strong': 'var(--app-info-fg)',
  '--callout-warning-bg': 'var(--app-warning-bg)',
  '--callout-warning-border': 'var(--app-warning-border)',
  '--callout-warning-icon': 'var(--app-warning-fg)',
  '--callout-warning-strong': 'var(--app-warning-fg)',
  '--callout-danger-bg': 'var(--app-danger-bg)',
  '--callout-danger-border': 'var(--app-danger-border)',
  '--callout-danger-icon': 'var(--app-danger-fg)',
  '--callout-danger-strong': 'var(--app-danger-fg)',
  '--callout-tip-bg': 'var(--app-tip-bg)',
  '--callout-tip-border': 'var(--app-tip-border)',
  '--callout-tip-icon': 'var(--app-tip-fg)',
  '--callout-tip-strong': 'var(--app-tip-fg)',
} as CSSProperties;

/** The public site around docs and the changelog: navbar, search, and the mobile navigation drawer. */
export function DocsShell({ active, currentSlug = '', children }: Props) {
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);

  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        setSearchOpen(true);
      }
      if (e.key === 'Escape') {
        setSearchOpen(false);
      }
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, []);

  return (
    <div className={classes.docsRoot} style={THEME}>
      <DocsNavBar active={active} onMenuClick={() => setDrawerOpen(true)} onSearchClick={() => setSearchOpen(true)} />

      {children}

      <Drawer
        opened={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        position="left"
        size={280}
        withCloseButton
        classNames={{
          content: classes.mobileDrawerContent,
          header: classes.mobileDrawerHeader,
          body: classes.mobileDrawerBody,
        }}
        aria-label="Navigation menu"
      >
        <nav className={classes.drawerSections} aria-label="Site sections">
          {DOCS_SECTIONS.map((section) => (
            <Link
              key={section.id}
              href={section.href}
              className={`${classes.sbItem} ${section.id === active ? classes.sbItemActive : ''}`}
              aria-current={section.id === active ? 'page' : undefined}
              onClick={() => setDrawerOpen(false)}
            >
              {section.label}
            </Link>
          ))}
        </nav>
        <DocsSidebar currentSlug={currentSlug} onNavigate={() => setDrawerOpen(false)} />
      </Drawer>

      <DocsSearchModal open={searchOpen} onClose={() => setSearchOpen(false)} />
    </div>
  );
}
