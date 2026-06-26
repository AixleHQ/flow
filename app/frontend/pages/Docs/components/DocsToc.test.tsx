import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';
import { renderPage, screen, userEvent, within } from 'test/renderPage';

import { type TocItem } from '../data/pages';
import { DocsToc } from './DocsToc';

const toc: TocItem[] = [
  { id: 'overview', text: 'Overview', level: 2 },
  { id: 'details', text: 'Sub Details', level: 3 },
  { id: 'wrap-up', text: 'Wrap Up', level: 2 },
];

describe('Docs/components/DocsToc', () => {
  it('renders nothing when the toc is empty', () => {
    renderPage(<DocsToc toc={[]} slug="quick-start" />);

    expect(screen.queryByRole('navigation', { name: 'Table of contents' })).not.toBeInTheDocument();
    expect(screen.queryByText('On this page')).not.toBeInTheDocument();
  });

  it('renders the table-of-contents nav with a link per item', () => {
    renderPage(<DocsToc toc={toc} slug="quick-start" />);

    const nav = screen.getByRole('navigation', { name: 'Table of contents' });
    expect(within(nav).getByText('On this page')).toBeInTheDocument();

    const links = within(nav).getAllByRole('link');
    expect(links).toHaveLength(3);
    expect(within(nav).getByRole('link', { name: 'Overview' })).toBeInTheDocument();
    expect(within(nav).getByRole('link', { name: 'Sub Details' })).toBeInTheDocument();
    expect(within(nav).getByRole('link', { name: 'Wrap Up' })).toBeInTheDocument();
  });

  it('points each link at the matching heading anchor', () => {
    renderPage(<DocsToc toc={toc} slug="quick-start" />);

    expect(screen.getByRole('link', { name: 'Overview' })).toHaveAttribute('href', '#overview');
    expect(screen.getByRole('link', { name: 'Sub Details' })).toHaveAttribute('href', '#details');
    expect(screen.getByRole('link', { name: 'Wrap Up' })).toHaveAttribute('href', '#wrap-up');
  });

  it('scrolls the target heading into view on click instead of doing a hard navigation', async () => {
    const heading = document.createElement('h2');
    heading.id = 'overview';
    const scrollSpy = vi.fn();
    heading.scrollIntoView = scrollSpy;
    document.body.appendChild(heading);

    renderPage(<DocsToc toc={toc} slug="quick-start" />);

    await userEvent.click(screen.getByRole('link', { name: 'Overview' }));

    expect(scrollSpy).toHaveBeenCalledWith({ behavior: 'smooth', block: 'start' });

    heading.remove();
  });

  it('does not throw when clicking a link whose heading is not present in the DOM', async () => {
    renderPage(<DocsToc toc={toc} slug="quick-start" />);

    // No element with id "wrap-up" exists -> the click handler must no-op safely.
    await userEvent.click(screen.getByRole('link', { name: 'Wrap Up' }));

    expect(screen.getByRole('link', { name: 'Wrap Up' })).toBeInTheDocument();
  });
});
