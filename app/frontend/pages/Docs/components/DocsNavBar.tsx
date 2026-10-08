import { Link, usePage } from '@inertiajs/react';
import { IconBrandGithub, IconMenu2, IconSearch } from '@tabler/icons-react';

import { Logo } from 'shared/ui/Logo';

import { DOCS_SECTIONS, type DocsSection } from '../data/sections';
import classes from '../DocsPage.module.css';

const starCount = new Intl.NumberFormat('en', { notation: 'compact', maximumFractionDigits: 1 });

interface Props {
  active: DocsSection;
  onMenuClick: () => void;
  onSearchClick: () => void;
}

export function DocsNavBar({ active, onMenuClick, onSearchClick }: Props) {
  // Deferred: absent until the follow-up request lands, null when GitHub could not be read.
  const { githubStars } = usePage<{ githubStars?: number | null }>().props;

  return (
    <header className={classes.navbar}>
      <button type="button" className={classes.hamburger} onClick={onMenuClick} aria-label="Open navigation menu">
        <IconMenu2 size={18} />
      </button>

      <Link href="/docs" className={classes.navLogo} aria-label="Aixle Flow docs">
        <Logo width={60} colorScheme="dark" />
        <span className={classes.navBrandFlow}>Flow</span>
      </Link>

      <nav className={classes.navLinks} aria-label="Site sections">
        {DOCS_SECTIONS.map((section) => (
          <Link
            key={section.id}
            href={section.href}
            className={`${classes.navLink} ${section.id === active ? classes.navLinkActive : ''}`}
            aria-current={section.id === active ? 'page' : undefined}
          >
            {section.label}
          </Link>
        ))}
      </nav>

      <div className={classes.navbarRight}>
        <button type="button" className={classes.searchTrigger} onClick={onSearchClick} aria-label="Open search">
          <IconSearch size={13} style={{ color: 'var(--app-text-tertiary)' }} />
          <span className={classes.searchTriggerText}>Search docs...</span>
          <span className={classes.searchKbd}>⌘K</span>
        </button>

        <a
          href="https://github.com/aixleHQ/flow"
          target="_blank"
          rel="noopener noreferrer"
          className={classes.githubLink}
        >
          <IconBrandGithub size={15} />
          GitHub
          {typeof githubStars === 'number' && (
            <span className={classes.githubStars}>★ {starCount.format(githubStars).toLowerCase()}</span>
          )}
        </a>
      </div>
    </header>
  );
}
