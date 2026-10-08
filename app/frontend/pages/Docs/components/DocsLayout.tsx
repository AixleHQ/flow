import { Link } from '@inertiajs/react';
import { IconChevronRight } from '@tabler/icons-react';
import { type ReactNode } from 'react';

import { type NavItem, getPrevNext } from '../data/navStructure';
import { type TocItem } from '../data/pages';
import { API_SLUG } from '../data/sections';
import classes from '../DocsPage.module.css';

import { DocsBreadcrumb } from './DocsBreadcrumb';
import { DocsShell } from './DocsShell';
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
  const { prev, next } = getPrevNext(slug);

  return (
    <DocsShell active={slug === API_SLUG ? 'api' : 'docs'} currentSlug={slug}>
      <div className={classes.bodyLayout}>
        <DocsSidebar currentSlug={slug} />

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
    </DocsShell>
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
