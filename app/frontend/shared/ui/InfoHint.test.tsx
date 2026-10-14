import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { act, renderPage as render, screen, userEvent } from 'test/renderPage';

import { InfoHint } from './InfoHint';

describe('InfoHint', () => {
  it('shows the hint in a Mantine tooltip on hover', async () => {
    render(<InfoHint label="The AI model that executes this session" />);

    await userEvent.hover(screen.getByRole('img', { name: 'The AI model that executes this session' }));

    expect(await screen.findByRole('tooltip')).toHaveTextContent('The AI model that executes this session');
  });

  it('shows the hint when focused from the keyboard', async () => {
    render(<InfoHint label="Waits for these sessions before starting" />);

    act(() => screen.getByRole('img').focus());

    expect(await screen.findByRole('tooltip')).toHaveTextContent('Waits for these sessions before starting');
  });
});
