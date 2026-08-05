import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage as render, screen } from 'test/renderPage';

import { Identicon } from './Identicon';

// Pure 25-cell <span> grid with no role/text, so assertions read the DOM
// directly via `document` rather than through RTL's container object.
const cellBackgrounds = () => [...document.querySelectorAll('span')].map((el) => el.style.background);

describe('Identicon', () => {
  it('renders the same 25-cell pattern for the same seed', () => {
    render(<Identicon seed="Acme" />);
    const first = cellBackgrounds();
    expect(first).toHaveLength(25);

    document.body.innerHTML = '';
    render(<Identicon seed="Acme" />);
    expect(cellBackgrounds()).toEqual(first);
  });

  it('renders a different pattern for a different seed', () => {
    render(<Identicon seed="Acme" />);
    const first = cellBackgrounds();

    document.body.innerHTML = '';
    render(<Identicon seed="Globex" />);
    expect(cellBackgrounds()).not.toEqual(first);
  });

  it('is decorative, not exposed to the accessibility tree', () => {
    render(<Identicon seed="Acme" />);
    expect(screen.queryByRole('img')).not.toBeInTheDocument();
    expect(document.querySelector('[aria-hidden="true"]')).toBeInTheDocument();
  });
});
