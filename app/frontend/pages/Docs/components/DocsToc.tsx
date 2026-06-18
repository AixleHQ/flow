import { useEffect, useState } from 'react';

import { type TocItem } from '../data/pages';
import classes from '../DocsPage.module.css';

interface Props {
  toc: TocItem[];
  slug: string;
}

export function DocsToc({ toc, slug }: Props) {
  const [activeId, setActiveId] = useState<string>('');

  useEffect(() => {
    if (toc.length === 0) return;

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            setActiveId(entry.target.id);
          }
        });
      },
      { rootMargin: '-20% 0px -70% 0px', threshold: 0 },
    );

    const headingEls = document.querySelectorAll('.docs-content h2, .docs-content h3');
    headingEls.forEach((el) => observer.observe(el));

    return () => observer.disconnect();
  }, [slug, toc]);

  if (toc.length === 0) return null;

  return (
    <nav className={classes.toc} aria-label="Table of contents">
      <p className={classes.tocTitle}>On this page</p>
      <ul className={classes.tocList}>
        {toc.map((item) => (
          <li key={item.id} className={classes.tocItem}>
            <a
              href={`#${item.id}`}
              className={`${classes.tocLink} ${item.level === 3 ? classes.tocLinkIndented : ''} ${
                activeId === item.id ? classes.tocLinkActive : ''
              }`}
              onClick={(e) => {
                e.preventDefault();
                const el = document.getElementById(item.id);
                if (el) {
                  el.scrollIntoView({ behavior: 'smooth', block: 'start' });
                  setActiveId(item.id);
                }
              }}
            >
              {item.text}
            </a>
          </li>
        ))}
      </ul>
    </nav>
  );
}
