import agents from './agents.md?raw';
import apiGuide from './api-guide.md?raw';
import board from './board.md?raw';
import changelogProductAreas from './changelog-product-areas.md?raw';
import cliRef from './cli-ref.md?raw';
import configSchema from './config-schema.md?raw';
import configuration from './configuration.md?raw';
import integrations from './integrations.md?raw';
import mcp from './mcp.md?raw';
import quickStart from './quick-start.md?raw';
import reference from './reference.md?raw';
import runtimes from './runtimes.md?raw';
import tools from './tools.md?raw';
import triggersAndGates from './triggers-and-gates.md?raw';
import userGuideOutline from './user-guide-outline.md?raw';
import userGuide from './user-guide.md?raw';
import workflows from './workflows.md?raw';

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

export const DOC_PAGES: Record<string, DocPage & { toc: TocItem[] }> = {
  'user-guide': {
    title: 'User Guide',
    section: 'User guide',
    content: userGuide,
    toc: extractToc(userGuide),
  },
  'quick-start': {
    title: 'Quick start',
    section: 'User guide',
    content: quickStart,
    toc: extractToc(quickStart),
  },
  agents: {
    title: 'Agents',
    section: 'User guide',
    content: agents,
    toc: extractToc(agents),
  },
  runtimes: {
    title: 'Runtimes',
    section: 'User guide',
    content: runtimes,
    toc: extractToc(runtimes),
  },
  tools: {
    title: 'Tools',
    section: 'User guide',
    content: tools,
    toc: extractToc(tools),
  },
  mcp: {
    title: 'MCP servers',
    section: 'User guide',
    content: mcp,
    toc: extractToc(mcp),
  },
  board: {
    title: 'Board',
    section: 'User guide',
    content: board,
    toc: extractToc(board),
  },
  workflows: {
    title: 'Workflows',
    section: 'User guide',
    content: workflows,
    toc: extractToc(workflows),
  },
  'triggers-and-gates': {
    title: 'Triggers and Gates',
    section: 'User guide',
    content: triggersAndGates,
    toc: extractToc(triggersAndGates),
  },
  integrations: {
    title: 'Integrations',
    section: 'User guide',
    content: integrations,
    toc: extractToc(integrations),
  },
  configuration: {
    title: 'Configuration',
    section: 'User guide',
    content: configuration,
    toc: extractToc(configuration),
  },
  reference: {
    title: 'Reference',
    section: 'Reference',
    content: reference,
    toc: extractToc(reference),
  },
  'cli-ref': {
    title: 'CLI reference',
    section: 'Reference',
    content: cliRef,
    toc: extractToc(cliRef),
  },
  'api-guide': {
    title: 'API',
    section: 'Reference',
    content: apiGuide,
    toc: extractToc(apiGuide),
  },
  'config-schema': {
    title: 'Configuration reference',
    section: 'Reference',
    content: configSchema,
    toc: extractToc(configSchema),
  },
  'user-guide-outline': {
    title: 'User guide outline',
    section: 'Product',
    content: userGuideOutline,
    toc: extractToc(userGuideOutline),
  },
  'changelog-product-areas': {
    title: 'Changelog product areas',
    section: 'Product',
    content: changelogProductAreas,
    toc: extractToc(changelogProductAreas),
  },
};

export function getDocPage(slug: string): (DocPage & { toc: TocItem[] }) | null {
  // Case-insensitive lookup
  const normalized = slug.toLowerCase();
  return DOC_PAGES[normalized] ?? null;
}
