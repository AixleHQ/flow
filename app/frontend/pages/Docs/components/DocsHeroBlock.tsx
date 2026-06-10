import {
  IconBrandGithub,
  IconPlug,
  IconRobot,
  IconRocket,
  IconShield,
  IconSubtask,
  IconTerminal,
} from '@tabler/icons-react';

import classes from '../DocsPage.module.css';

interface ConceptCard {
  icon: typeof IconRobot;
  name: string;
  desc: string;
  href: string;
}

const CARDS: ConceptCard[] = [
  {
    icon: IconRobot,
    name: 'Agents',
    desc: 'Autonomous workers that receive a goal and execute the steps needed to reach it.',
    href: '/docs/agents',
  },
  {
    icon: IconSubtask,
    name: 'Tasks',
    desc: 'A single unit of work. Tasks can be chained, parallelised, or triggered by events.',
    href: '#',
  },
  {
    icon: IconPlug,
    name: 'Integrations',
    desc: 'Connect to GitHub, Vercel, AWS and more. Agents act on your behalf.',
    href: '#',
  },
  {
    icon: IconShield,
    name: 'Permissions',
    desc: 'Fine-grained access control over what each agent can read, write, or deploy.',
    href: '#',
  },
];

export function DocsHeroBlock() {
  return (
    <>
      <div className={classes.heroTags}>
        <span className={classes.heroTag}>Open source</span>
        <span className={classes.heroTag}>v0.4.2</span>
      </div>

      <div className={classes.heroChips}>
        <a href="/docs/quick-start" className={classes.chipPrimary}>
          <IconRocket size={14} />
          Quick start
        </a>
        <a href="#" className={classes.chipSecondary}>
          <IconTerminal size={14} />
          Run your first task
        </a>
        <a href="https://github.com" target="_blank" rel="noopener noreferrer" className={classes.chipSecondary}>
          {' '}
          <IconBrandGithub size={14} />
          View on GitHub
        </a>
      </div>
    </>
  );
}

export function DocsConceptCards() {
  return (
    <div className={classes.conceptCardGrid}>
      {CARDS.map(({ icon: Icon, name, desc, href }) => (
        <a key={name} href={href} className={classes.conceptCard}>
          <span className={classes.conceptCardIcon}>
            <Icon size={15} />
          </span>
          <span className={classes.conceptCardName}>{name}</span>
          <span className={classes.conceptCardDesc}>{desc}</span>
        </a>
      ))}
    </div>
  );
}
