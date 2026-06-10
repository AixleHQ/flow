import agents from './agents.md?raw';
import quickStart from './quick-start.md?raw';
import whatIsAixle from './what-is-aixle.md?raw';

export interface TocItem {
  id: string;
  text: string;
  level: 2 | 3;
}

export interface DocPage {
  title: string;
  section: string;
  content: string;
}

function extractToc(markdown: string): TocItem[] {
  const toc: TocItem[] = [];
  const lines = markdown.split('\n');
  for (const line of lines) {
    const h2 = line.match(/^## (.+)$/);
    const h3 = line.match(/^### (.+)$/);
    if (h2) {
      const text = h2[1].trim();
      toc.push({ id: slugify(text), text, level: 2 });
    } else if (h3) {
      const text = h3[1].trim();
      toc.push({ id: slugify(text), text, level: 3 });
    }
  }
  return toc;
}

function slugify(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-');
}

const STUB_CONTENT = `## Coming soon

This page is under development. Check back soon for more information.`;

export const DOC_PAGES: Record<string, DocPage & { toc: TocItem[] }> = {
  'what-is-aixle': {
    title: 'What is Aixle',
    section: 'Getting started',
    content: whatIsAixle,
    toc: extractToc(whatIsAixle),
  },
  'quick-start': {
    title: 'Quick start',
    section: 'Getting started',
    content: quickStart,
    toc: extractToc(quickStart),
  },
  agents: {
    title: 'Agents',
    section: 'Core concepts',
    content: agents,
    toc: extractToc(agents),
  },
  'install-guide': {
    title: 'Installation guide',
    section: 'Getting started',
    content: STUB_CONTENT,
    toc: extractToc(STUB_CONTENT),
  },
  configuration: {
    title: 'Configuration',
    section: 'Getting started',
    content: STUB_CONTENT,
    toc: extractToc(STUB_CONTENT),
  },
  'self-hosting': {
    title: 'Self-hosting',
    section: 'Getting started',
    content: STUB_CONTENT,
    toc: extractToc(STUB_CONTENT),
  },
  cli: {
    title: 'CLI setup',
    section: 'Getting started',
    content: STUB_CONTENT,
    toc: extractToc(STUB_CONTENT),
  },
  'tasks-overview': {
    title: 'Tasks',
    section: 'Core concepts',
    content: STUB_CONTENT,
    toc: extractToc(STUB_CONTENT),
  },
  tasks: {
    title: 'Tasks Overview',
    section: 'Core concepts',
    content: STUB_CONTENT,
    toc: extractToc(STUB_CONTENT),
  },
  integrations: {
    title: 'Integrations',
    section: 'Core concepts',
    content: STUB_CONTENT,
    toc: extractToc(STUB_CONTENT),
  },
  permissions: {
    title: 'Permissions',
    section: 'Core concepts',
    content: STUB_CONTENT,
    toc: extractToc(STUB_CONTENT),
  },
  deploy: {
    title: 'Deploy a repo',
    section: 'Guides',
    content: STUB_CONTENT,
    toc: extractToc(STUB_CONTENT),
  },
  'api-guide': {
    title: 'Use the API',
    section: 'Guides',
    content: STUB_CONTENT,
    toc: extractToc(STUB_CONTENT),
  },
  advanced: {
    title: 'Advanced',
    section: 'Guides',
    content: STUB_CONTENT,
    toc: extractToc(STUB_CONTENT),
  },
  'cli-ref': {
    title: 'CLI reference',
    section: 'Guides',
    content: STUB_CONTENT,
    toc: extractToc(STUB_CONTENT),
  },
  'config-schema': {
    title: 'Config schema',
    section: 'Guides',
    content: STUB_CONTENT,
    toc: extractToc(STUB_CONTENT),
  },
};

export function getDocPage(slug: string): (DocPage & { toc: TocItem[] }) | null {
  // Case-insensitive lookup
  const normalized = slug.toLowerCase();
  return DOC_PAGES[normalized] ?? null;
}
