import '@testing-library/jest-dom/vitest';

import { describe, expect, it } from 'vitest';

import { render, screen } from 'test/renderPage';

import { ContainerFrame } from './ContainerFrame';

const tty = (ticket: string) => `https://sandbox.example.com/t/abc/tty?aixle_ticket=${ticket}`;

describe('ContainerFrame', () => {
  it('keeps the URL it loaded while only the pass changes', () => {
    const { rerender } = render(<ContainerFrame src={tty('first')} title="Terminal" />);

    rerender(<ContainerFrame src={tty('second')} title="Terminal" />);

    expect(screen.getByTitle('Terminal')).toHaveAttribute('src', tty('first'));
  });

  it('follows a change of route', () => {
    const { rerender } = render(<ContainerFrame src={tty('first')} title="Terminal" />);

    rerender(<ContainerFrame src="https://sandbox.example.com/t/xyz/view?aixle_ticket=third" title="Terminal" />);

    expect(screen.getByTitle('Terminal')).toHaveAttribute(
      'src',
      'https://sandbox.example.com/t/xyz/view?aixle_ticket=third',
    );
  });

  it('takes the newest pass when it is mounted again', () => {
    const { unmount } = render(<ContainerFrame src={tty('first')} title="Terminal" />);
    unmount();

    render(<ContainerFrame src={tty('fourth')} title="Terminal" />);

    expect(screen.getByTitle('Terminal')).toHaveAttribute('src', tty('fourth'));
  });
});
