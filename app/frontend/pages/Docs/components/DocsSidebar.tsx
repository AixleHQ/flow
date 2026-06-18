import { Link } from '@inertiajs/react';
import { IconChevronRight } from '@tabler/icons-react';
import { useState } from 'react';

import { NAV_STRUCTURE, type NavItem, type NavSection } from '../data/navStructure';
import classes from '../DocsPage.module.css';

interface Props {
  currentSlug: string;
  onNavigate?: () => void;
}

function NavItemRow({
  item,
  currentSlug,
  depth,
  onNavigate,
}: {
  item: NavItem;
  currentSlug: string;
  depth: number;
  onNavigate?: () => void;
}) {
  const hasChildren = item.children && item.children.length > 0;
  const isActive = item.slug === currentSlug;
  const isChildActive = item.children?.some((c) => c.slug === currentSlug) ?? false;

  const [open, setOpen] = useState(isActive || isChildActive);

  if (hasChildren) {
    return (
      <li>
        <button
          type="button"
          className={`${classes.sbGroup} ${isActive || isChildActive ? classes.sbGroupActive : ''}`}
          onClick={() => setOpen((prev) => !prev)}
        >
          <span className={classes.sbGroupLabel}>{item.label}</span>
          {item.badge && <span className={classes.sbBadge}>{item.badge}</span>}
          <span className={`${classes.sbToggleIcon} ${open ? classes.sbToggleIconOpen : ''}`}>
            <IconChevronRight size={12} />
          </span>
        </button>
        {open && (
          <ul className={classes.sbChildList}>
            {item.children!.map((child) => (
              <NavItemRow
                key={child.slug}
                item={child}
                currentSlug={currentSlug}
                depth={depth + 1}
                onNavigate={onNavigate}
              />
            ))}
          </ul>
        )}
      </li>
    );
  }

  const isSubItem = depth > 0;

  return (
    <li>
      <Link
        href={`/docs/${item.slug}`}
        className={
          isSubItem
            ? `${classes.sbSubItem} ${isActive ? classes.sbSubItemActive : ''}`
            : `${classes.sbItem} ${isActive ? classes.sbItemActive : ''}`
        }
        onClick={onNavigate}
      >
        {item.label}
        {item.badge && <span className={classes.sbBadge}>{item.badge}</span>}
      </Link>
    </li>
  );
}

function NavSectionBlock({
  section,
  currentSlug,
  onNavigate,
}: {
  section: NavSection;
  currentSlug: string;
  onNavigate?: () => void;
}) {
  return (
    <div className={classes.sbSection}>
      <span className={classes.sbSectionLabel}>{section.label}</span>
      <div className={classes.sbItems}>
        <ul className={classes.sbList}>
          {section.items.map((item) => (
            <NavItemRow key={item.slug} item={item} currentSlug={currentSlug} depth={0} onNavigate={onNavigate} />
          ))}
        </ul>
      </div>
    </div>
  );
}

export function DocsSidebar({ currentSlug, onNavigate }: Props) {
  return (
    <nav className={classes.sidebar} aria-label="Documentation navigation">
      {NAV_STRUCTURE.map((section) => (
        <NavSectionBlock key={section.label} section={section} currentSlug={currentSlug} onNavigate={onNavigate} />
      ))}
    </nav>
  );
}
