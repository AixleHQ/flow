import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage as render, screen } from 'test/renderPage';

import { BrandLockup } from './BrandLockup';

describe('BrandLockup', () => {
  it('names the product as one image', () => {
    render(<BrandLockup size="lg" />);

    expect(screen.getByRole('img', { name: 'Aixle Flow' })).toBeInTheDocument();
  });
});
