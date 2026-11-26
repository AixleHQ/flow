import { describe, expect, it } from 'vitest';

import { buildBoardTask } from 'test/factories/boardTask';
import { renderPage, screen } from 'test/renderPage';

import { TaskCardUI } from './TaskCardUI';
import type { Task } from './types';

const renderCard = (title: string) => renderPage(<TaskCardUI task={buildBoardTask({ title }) as Task} />);

describe('TaskCardUI title', () => {
  it('cuts a long title to 300 characters plus an ellipsis and keeps the full title on hover', () => {
    const title = 'a'.repeat(400);
    renderCard(title);

    const shown = screen.getByText(`${'a'.repeat(300)}…`);
    expect(shown).toHaveAttribute('title', title);
  });

  it('shows a short title as is, without a hover title', () => {
    renderCard('Fix login');

    expect(screen.getByText('Fix login')).not.toHaveAttribute('title');
  });
});
