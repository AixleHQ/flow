import { Link } from '@inertiajs/react';
import { Drawer } from '@mantine/core';
import { IconChevronRight } from '@tabler/icons-react';
import { useEffect, useState, type ReactNode } from 'react';

import { type NavItem, getPrevNext } from '../data/navStructure';
import { type TocItem } from '../data/pages';
import classes from '../DocsPage.module.css';

import { DocsBreadcrumb } from './DocsBreadcrumb';
import { DocsNavBar } from './DocsNavBar';
import { DocsSearchModal } from './DocsSearchModal';
import { DocsSidebar } from './DocsSidebar';
import { DocsToc } from './DocsToc';

interface Props {
  slug: string;
  title: string;
  section: string;
  toc: TocItem[];
  children: ReactNode;
}

export function DocsLayout({ slug, title, section, toc, children }: Props) {
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const { prev, next } = getPrevNext(slug);

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
    <div
      className={classes.docsRoot}
      style={
        {
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
          '--mantine-color-blue-5': 'var(--mantine-color-brand-5)',
          '--mantine-color-blue-6': 'var(--mantine-color-brand-6)',
          '--mantine-color-blue-7': 'var(--mantine-color-brand-7)',
          '--mantine-color-blue-8': 'var(--mantine-color-brand-8)',
          '--mantine-color-blue-9': 'var(--mantine-color-brand-9)',
          '--callout-info-bg': 'rgba(122, 162, 200, 0.05)',
          '--callout-info-border': '#2a3e52',
          '--callout-info-icon': '#4e7494',
          '--callout-info-strong': '#6a8faa',
          '--callout-warning-bg': 'rgba(180, 148, 60, 0.05)',
          '--callout-warning-border': '#3a3020',
          '--callout-warning-icon': '#7a6430',
          '--callout-warning-strong': '#8a7440',
          '--callout-danger-bg': 'rgba(180, 80, 80, 0.05)',
          '--callout-danger-border': '#3a2020',
          '--callout-danger-icon': '#7a3838',
          '--callout-danger-strong': '#8a4848',
          '--callout-tip-bg': 'rgba(100, 70, 180, 0.05)',
          '--callout-tip-border': '#2a2040',
          '--callout-tip-icon': '#5a4880',
          '--callout-tip-strong': '#6a5890',
        } as React.CSSProperties
      }
    >
      <DocsNavBar onMenuClick={() => setDrawerOpen(true)} onSearchClick={() => setSearchOpen(true)} />

      <div className={classes.bodyLayout}>
        <DocsSidebar currentSlug={slug} onNavigate={() => setDrawerOpen(false)} />

        <main className={`${classes.mainContent} docs-content`}>
          <DocsBreadcrumb section={section} title={title} />

          <article className={classes.article}>{children}</article>

          <nav className={classes.pageNav} aria-label="Previous and next pages">
            {prev ? <PrevNextLink dir="prev" item={prev} /> : <span />}
            {next ? <PrevNextLink dir="next" item={next} /> : <span />}
          </nav>
        </main>

        <DocsToc toc={toc} slug={slug} />
      </div>

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
        <DocsSidebar currentSlug={slug} onNavigate={() => setDrawerOpen(false)} />
      </Drawer>

      <DocsSearchModal open={searchOpen} onClose={() => setSearchOpen(false)} />
    </div>
  );
}

function PrevNextLink({ dir, item }: { dir: 'prev' | 'next'; item: NavItem }) {
  return (
    <Link
      href={`/docs/${item.slug}`}
      className={`${classes.pageNavItem} ${dir === 'next' ? classes.pageNavNext : classes.pageNavPrev}`}
    >
      {dir === 'prev' && (
        <>
          <span className={classes.pageNavLabel}>← Previous</span>
          <span className={classes.pageNavTitle}>{item.label}</span>
        </>
      )}
      {dir === 'next' && (
        <>
          <span className={classes.pageNavLabel}>Next →</span>
          <span className={classes.pageNavTitle}>
            {item.label}
            <IconChevronRight size={14} />
          </span>
        </>
      )}
    </Link>
  );
}
