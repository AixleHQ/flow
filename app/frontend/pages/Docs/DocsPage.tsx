import { Head, usePage } from '@inertiajs/react';

import { DocsConceptCards, DocsHeroBlock } from './components/DocsHeroBlock';
import { DocsLayout } from './components/DocsLayout';
import { DocsMdxContent } from './components/DocsMdxContent';
import { getDocPage } from './data/pages';

/** Split markdown at the first occurrence of a heading so we can inject React between sections. */
function splitAtHeading(content: string, heading: string): [string, string] {
  const idx = content.indexOf(heading);
  if (idx === -1) return [content, ''];
  return [content.slice(0, idx), content.slice(idx)];
}

const DocsPage = () => {
  const props = usePage().props as { slug?: string };
  const slug = props.slug ?? 'what-is-aixle';
  const page = getDocPage(slug);

  if (!page) {
    return (
      <>
        <Head title="Page not found — Aixle Docs" />
        <DocsLayout slug={slug} title="Not found" section="Docs" toc={[]}>
          <h1>Page not found</h1>
          <p>The documentation page &ldquo;{slug}&rdquo; does not exist yet.</p>
        </DocsLayout>
      </>
    );
  }

  if (slug === 'what-is-aixle') {
    const [beforeHowItWorks, fromHowItWorks] = splitAtHeading(page.content, '## How it works');
    return (
      <>
        <Head title={`${page.title} — Aixle Docs`} />
        <DocsLayout slug={slug} title={page.title} section={page.section} toc={page.toc}>
          <DocsHeroBlock />
          <DocsMdxContent content={beforeHowItWorks} />
          <DocsConceptCards />
          <DocsMdxContent content={fromHowItWorks} />
        </DocsLayout>
      </>
    );
  }

  return (
    <>
      <Head title={`${page.title} — Aixle Docs`} />
      <DocsLayout slug={slug} title={page.title} section={page.section} toc={page.toc}>
        <DocsMdxContent content={page.content} />
      </DocsLayout>
    </>
  );
};

export default DocsPage;
