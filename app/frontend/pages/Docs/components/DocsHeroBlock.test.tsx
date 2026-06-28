import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen, within } from 'test/renderPage';

import { DocsConceptCards, DocsHeroBlock } from './DocsHeroBlock';

// Both exports are static presentational blocks (no props, no usePage, no forms),
// so renderPage is used directly and assertions are by visible text / link role.
describe('Docs/components/DocsHeroBlock', () => {
  describe('DocsHeroBlock', () => {
    it('renders the status tags', () => {
      renderPage(<DocsHeroBlock />);

      expect(screen.getByText('Open source')).toBeInTheDocument();
      expect(screen.getByText('v0.4.2')).toBeInTheDocument();
    });

    it('renders the primary "Quick start" chip pointing at the quick-start doc', () => {
      renderPage(<DocsHeroBlock />);

      const quickStart = screen.getByRole('link', { name: /Quick start/ });
      expect(quickStart).toHaveAttribute('href', '/docs/quick-start');
    });

    it('renders the GitHub chip as an external link opening in a new tab safely', () => {
      renderPage(<DocsHeroBlock />);

      const github = screen.getByRole('link', { name: /View on GitHub/ });
      expect(github).toHaveAttribute('href', 'https://github.com');
      expect(github).toHaveAttribute('target', '_blank');
      expect(github).toHaveAttribute('rel', 'noopener noreferrer');
    });

    it('renders all three chip links', () => {
      renderPage(<DocsHeroBlock />);

      expect(screen.getByRole('link', { name: /Quick start/ })).toBeInTheDocument();
      expect(screen.getByRole('link', { name: /Run your first task/ })).toBeInTheDocument();
      expect(screen.getByRole('link', { name: /View on GitHub/ })).toBeInTheDocument();
    });
  });

  describe('DocsConceptCards', () => {
    it('renders a card for each concept with its name and description', () => {
      renderPage(<DocsConceptCards />);

      // Card accessible name is "<name> <desc>"; anchor to the start so the
      // "Agents" card is not also matched by the Integrations description
      // ("...Agents act on your behalf.").
      const names = ['Agents', 'Tasks', 'Integrations', 'Permissions'];
      names.forEach((name) => {
        const card = screen.getByRole('link', { name: new RegExp(`^${name}`) });
        expect(card).toBeInTheDocument();
      });

      expect(screen.getByText(/Autonomous workers that receive a goal/)).toBeInTheDocument();
      expect(screen.getByText(/Fine-grained access control/)).toBeInTheDocument();
    });

    it('links the Agents card to its doc page and stubs the rest', () => {
      renderPage(<DocsConceptCards />);

      const agents = screen.getByRole('link', { name: /^Agents/ });
      expect(agents).toHaveAttribute('href', '/docs/agents');

      // The Tasks card is a not-yet-wired placeholder ("#").
      const tasks = screen.getByRole('link', { name: /^Tasks/ });
      expect(tasks).toHaveAttribute('href', '#');
    });

    it('groups the name and description inside the same card link', () => {
      renderPage(<DocsConceptCards />);

      const integrations = screen.getByRole('link', { name: /^Integrations/ });
      expect(within(integrations).getByText('Integrations')).toBeInTheDocument();
      expect(within(integrations).getByText(/Connect to GitHub, Vercel, AWS/)).toBeInTheDocument();
    });
  });
});
