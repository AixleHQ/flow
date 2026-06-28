import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen } from 'test/renderPage';

import { DocsCallout } from './DocsCallout';

// DocsCallout is a presentational wrapper: it renders its children inside a body
// and picks an icon based on the `variant` prop. Tabler icons render an <svg>
// whose `tabler-icon-*` class identifies which icon was chosen (the component's
// core variant->icon mapping). All other assertions are on visible content/roles.
describe('Docs/components/DocsCallout', () => {
  it('renders its children content', () => {
    const { container } = renderPage(
      <DocsCallout>
        <p>Heads up about the relay subsystem.</p>
      </DocsCallout>,
    );

    expect(screen.getByText('Heads up about the relay subsystem.')).toBeInTheDocument();
    // Default variant renders an svg icon alongside the body.
    expect(container.querySelector('svg')).toBeInTheDocument();
  });

  it('renders rich children including interactive elements and headings', () => {
    renderPage(
      <DocsCallout variant="tip">
        <h4>Pro tip</h4>
        <a href="/docs/agents">See the agents guide</a>
      </DocsCallout>,
    );

    expect(screen.getByRole('heading', { name: 'Pro tip' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'See the agents guide' })).toHaveAttribute('href', '/docs/agents');
  });

  it('defaults to the info variant and renders the info-circle icon', () => {
    const { container } = renderPage(<DocsCallout>Informational note</DocsCallout>);

    expect(screen.getByText('Informational note')).toBeInTheDocument();
    expect(container.querySelector('svg.tabler-icon-info-circle')).toBeInTheDocument();
  });

  it('renders the alert-triangle icon for the warning variant', () => {
    const { container } = renderPage(<DocsCallout variant="warning">Be careful here</DocsCallout>);

    expect(screen.getByText('Be careful here')).toBeInTheDocument();
    expect(container.querySelector('svg.tabler-icon-alert-triangle')).toBeInTheDocument();
  });

  it('renders the alert-circle icon for the danger variant', () => {
    const { container } = renderPage(<DocsCallout variant="danger">This action is irreversible</DocsCallout>);

    expect(screen.getByText('This action is irreversible')).toBeInTheDocument();
    expect(container.querySelector('svg.tabler-icon-alert-circle')).toBeInTheDocument();
  });

  it('renders the bulb icon for the tip variant', () => {
    const { container } = renderPage(<DocsCallout variant="tip">A handy shortcut</DocsCallout>);

    expect(screen.getByText('A handy shortcut')).toBeInTheDocument();
    expect(container.querySelector('svg.tabler-icon-bulb')).toBeInTheDocument();
  });
});
