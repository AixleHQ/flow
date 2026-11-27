import { describe, expect, it } from 'vitest';

import { buildBoardTask } from 'test/factories/boardTask';
import { renderPage, screen, userEvent } from 'test/renderPage';

import { TaskCardUI } from './TaskCardUI';
import type { Task } from './types';

const renderCard = (title: string) => renderPage(<TaskCardUI task={buildBoardTask({ title }) as Task} />);

describe('TaskCardUI title', () => {
  it('cuts a long title to 300 characters plus an ellipsis and shows the full title in a padded tooltip on hover', async () => {
    const title = 'a'.repeat(400);
    renderCard(title);

    await userEvent.hover(screen.getByText(`${'a'.repeat(300)}…`));

    const tooltip = await screen.findByRole('tooltip');
    expect(tooltip).toHaveTextContent(title);
    expect(tooltip).toHaveStyle({ padding: '8px 12px' });
  });

  it('shows a short title as is, without a tooltip', async () => {
    renderCard('Fix login');

    await userEvent.hover(screen.getByText('Fix login'));

    expect(screen.queryByRole('tooltip')).not.toBeInTheDocument();
  });
});
