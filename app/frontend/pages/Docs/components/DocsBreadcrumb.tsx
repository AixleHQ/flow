import { Link } from '@inertiajs/react';
import { IconChevronRight } from '@tabler/icons-react';

import classes from '../DocsPage.module.css';

interface Props {
  section: string;
  title: string;
}

export function DocsBreadcrumb({ section, title }: Props) {
  return (
    <nav className={classes.breadcrumb} aria-label="Breadcrumb">
      <Link href="/docs" className={classes.breadcrumbLink}>
        Docs
      </Link>
      <IconChevronRight size={12} className={classes.breadcrumbSep} />
      <span className={classes.breadcrumbSection}>{section}</span>
      <IconChevronRight size={12} className={classes.breadcrumbSep} />
      <span className={classes.breadcrumbCurrent}>{title}</span>
    </nav>
  );
}
