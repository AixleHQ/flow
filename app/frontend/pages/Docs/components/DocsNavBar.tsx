import { Link } from '@inertiajs/react';
import { IconBrandGithub, IconMenu2, IconSearch } from '@tabler/icons-react';

import classes from '../DocsPage.module.css';

interface Props {
  onMenuClick: () => void;
  onSearchClick: () => void;
}

export function DocsNavBar({ onMenuClick, onSearchClick }: Props) {
  return (
    <header className={classes.navbar}>
      <button type="button" className={classes.hamburger} onClick={onMenuClick} aria-label="Open navigation menu">
        <IconMenu2 size={18} />
      </button>

      <Link href="/docs" className={classes.navLogo}>
        aix<span className={classes.navLogoAccent}>le</span>
      </Link>

      <nav className={classes.navLinks}>
        <Link href="/docs" className={`${classes.navLink} ${classes.navLinkActive}`}>
          Docs
        </Link>
        <Link href="/docs/api-guide" className={classes.navLink}>
          API
        </Link>
      </nav>

      <div className={classes.navbarRight}>
        <button type="button" className={classes.searchTrigger} onClick={onSearchClick} aria-label="Open search">
          <IconSearch size={13} style={{ color: 'var(--mantine-color-dark-2)' }} />
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
          <span className={classes.githubStars}>★ 2.4k</span>
        </a>
      </div>
    </header>
  );
}
