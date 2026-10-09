import { Head, usePage } from '@inertiajs/react';

import { DocsLayout } from './components/DocsLayout';
import { DocsMdxContent } from './components/DocsMdxContent';
import { getDocPage } from './data/pages';

const DocsPage = () => {
  const props = usePage().props as { slug?: string };
  const slug = props.slug ?? 'user-guide';
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
