import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen, within } from 'test/renderPage';

import { DocsMdxContent } from './DocsMdxContent';

// DocsMdxContent is a purely presentational markdown renderer driven by its `content`
// prop, so renderPage(<DocsMdxContent content=... />) is enough — it reads no usePage data.
describe('Docs/components/DocsMdxContent', () => {
  it('renders headings as the matching heading levels with slugified ids', () => {
    renderPage(<DocsMdxContent content={'# Getting Started\n\n## Install Steps\n\n### Sub Section'} />);

    const h1 = screen.getByRole('heading', { name: 'Getting Started', level: 1 });
    expect(h1).toBeInTheDocument();
    expect(h1).toHaveAttribute('id', 'getting-started');

    const h2 = screen.getByRole('heading', { name: 'Install Steps', level: 2 });
    expect(h2).toHaveAttribute('id', 'install-steps');

    expect(screen.getByRole('heading', { name: 'Sub Section', level: 3 })).toHaveAttribute('id', 'sub-section');
  });

  it('renders an external link with target/rel and an internal link without them', () => {
    renderPage(<DocsMdxContent content={'[Outside](https://example.com) and [Inside](/docs/agents)'} />);

    const external = screen.getByRole('link', { name: /Outside/ });
    expect(external).toHaveAttribute('href', 'https://example.com');
    expect(external).toHaveAttribute('target', '_blank');
    expect(external).toHaveAttribute('rel', 'noopener noreferrer');

    const internal = screen.getByRole('link', { name: 'Inside' });
    expect(internal).toHaveAttribute('href', '/docs/agents');
    expect(internal).not.toHaveAttribute('target');
    expect(internal).not.toHaveAttribute('rel');
  });

  it('renders a fenced code block via DocsCodeBlock with a language label and copy button', () => {
    renderPage(<DocsMdxContent content={'```typescript\nconst answer = 42;\n```'} />);

    // DocsCodeBlock maps the `typescript` fence to the "TypeScript" label.
    expect(screen.getByText('TypeScript')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Copy code to clipboard' })).toBeInTheDocument();
    // The syntax highlighter splits code into per-token spans, so assert a single token.
    expect(screen.getByText('const')).toBeInTheDocument();
    expect(screen.getByText('42')).toBeInTheDocument();
  });

  it('renders a blockquote whose keyword turns it into a callout with the keyword stripped', () => {
    renderPage(<DocsMdxContent content={'> tip Remember to save your work often.'} />);

    // The remarkCalloutType plugin removes the leading "tip" keyword from the text.
    expect(screen.getByText('Remember to save your work often.')).toBeInTheDocument();
    expect(screen.queryByText(/tip Remember/)).not.toBeInTheDocument();
  });

  it('renders GFM tables and lists from markdown', () => {
    renderPage(
      <DocsMdxContent
        content={['| Name | Role |', '| --- | --- |', '| Ada | Engineer |', '', '- first item', '- second item'].join(
          '\n',
        )}
      />,
    );

    const table = screen.getByRole('table');
    expect(within(table).getByRole('columnheader', { name: 'Name' })).toBeInTheDocument();
    expect(within(table).getByRole('cell', { name: 'Ada' })).toBeInTheDocument();

    const list = screen.getByRole('list');
    const items = within(list).getAllByRole('listitem');
    expect(items).toHaveLength(2);
    expect(items[0]).toHaveTextContent('first item');
  });

  it('renders an inline code span without the code-block copy chrome', () => {
    renderPage(<DocsMdxContent content={'Use the `yarn build` command to compile.'} />);

    expect(screen.getByText('yarn build')).toBeInTheDocument();
    // Inline code never renders the fenced block's copy button.
    expect(screen.queryByRole('button', { name: 'Copy code to clipboard' })).not.toBeInTheDocument();
  });
});
