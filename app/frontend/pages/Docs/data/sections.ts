export type DocsSection = 'docs' | 'api' | 'changelog';

export const API_SLUG = 'api-guide';

export const DOCS_SECTIONS: { id: DocsSection; label: string; href: string }[] = [
  { id: 'docs', label: 'Docs', href: '/docs' },
  { id: 'api', label: 'API', href: `/docs/${API_SLUG}` },
  { id: 'changelog', label: 'Changelog', href: '/changelog' },
];
