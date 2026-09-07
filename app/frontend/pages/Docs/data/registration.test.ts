import { describe, expect, it } from 'vitest';

import { NAV_STRUCTURE } from './navStructure';
import { DOC_PAGES } from './pages';
import { SEARCH_INDEX } from './searchIndex';

// A docs page is registered in three places: the page registry (content + title),
// the nav (where it appears), and the search index (how it is found). A page missing
// from any one of them is invisible in a way no page-level test would catch — the
// portal simply never links to it. These tests keep the three in step.

const navSlugs = NAV_STRUCTURE.flatMap((section) =>
  section.items.flatMap((item) => [item.slug, ...(item.children ?? []).map((child) => child.slug)]),
);

describe('docs page registration', () => {
  it('gives every nav entry a page to render', () => {
    const missing = navSlugs.filter((slug) => !(slug in DOC_PAGES));
    expect(missing).toEqual([]);
  });

  it('puts every page in the nav', () => {
    const missing = Object.keys(DOC_PAGES).filter((slug) => !navSlugs.includes(slug));
    expect(missing).toEqual([]);
  });

  it('makes every page findable through search', () => {
    const indexed = SEARCH_INDEX.map((entry) => entry.slug);
    const missing = Object.keys(DOC_PAGES).filter((slug) => !indexed.includes(slug));
    expect(missing).toEqual([]);
  });

  it('files each page under the section its nav entry lives in', () => {
    const mismatched = NAV_STRUCTURE.flatMap((section) =>
      section.items.filter((item) => DOC_PAGES[item.slug]?.section !== section.label).map((item) => item.slug),
    );
    expect(mismatched).toEqual([]);
  });

  it('describes every page in the search index it indexes', () => {
    const unknown = SEARCH_INDEX.filter((entry) => !(entry.slug in DOC_PAGES)).map((e) => e.slug);
    expect(unknown).toEqual([]);
  });
});
