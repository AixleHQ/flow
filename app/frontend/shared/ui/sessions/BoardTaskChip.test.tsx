import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen } from 'test/renderPage';

import { BoardTaskChip } from './BoardTaskChip';

describe('BoardTaskChip', () => {
  it('renders nothing without a board task', () => {
    renderPage(<BoardTaskChip projectId={7} boardTask={null} />);

    expect(screen.queryByRole('link', { name: /open board task/i })).not.toBeInTheDocument();
  });

  it('links to the board card with number and title', () => {
    renderPage(
      <BoardTaskChip projectId={7} boardTask={{ id: 142, title: 'Fix login timeout', archived: false }} />,
    );

    const link = screen.getByRole('link', { name: 'Open board task #142 Fix login timeout' });
    expect(link).toHaveAttribute('href', '/company/projects/7/board?task=142');
    expect(link).toHaveTextContent('#142');
    expect(link).toHaveTextContent('Fix login timeout');
  });

  it('still links when the task is archived', () => {
    renderPage(
      <BoardTaskChip projectId={7} boardTask={{ id: 9, title: 'Archived card', archived: true }} />,
    );

    expect(screen.getByRole('link', { name: /open board task #9 archived card/i })).toHaveAttribute(
      'href',
      '/company/projects/7/board?task=9',
    );
  });
});
