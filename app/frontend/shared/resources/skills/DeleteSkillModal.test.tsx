import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { DeleteSkillModal } from './DeleteSkillModal';

const skill = { id: 7, name: 'react_helper', title: 'React Helper' };

describe('DeleteSkillModal', () => {
  it('renders the confirmation prompt with the skill title when opened', () => {
    renderPage(
      <DeleteSkillModal opened onClose={vi.fn()} skill={skill} basePath="/projects/1/skills" />,
    );

    expect(screen.getByRole('heading', { name: /delete skill/i })).toBeInTheDocument();
    expect(screen.getByText(/this action cannot be undone/i)).toBeInTheDocument();
    expect(screen.getByText('React Helper')).toBeInTheDocument();
  });

  it('falls back to the skill name when title is null', () => {
    renderPage(
      <DeleteSkillModal
        opened
        onClose={vi.fn()}
        skill={{ id: 9, name: 'no_title_skill', title: null }}
        basePath="/projects/1/skills"
      />,
    );

    expect(screen.getByText('no_title_skill')).toBeInTheDocument();
  });

  it('renders no modal content when skill is null', () => {
    renderPage(
      <DeleteSkillModal opened onClose={vi.fn()} skill={null} basePath="/projects/1/skills" />,
    );

    expect(screen.queryByRole('heading', { name: /delete skill/i })).not.toBeInTheDocument();
    expect(screen.queryByText(/this action cannot be undone/i)).not.toBeInTheDocument();
  });

  it('confirming Delete fires router.delete with the skill path', async () => {
    renderPage(
      <DeleteSkillModal opened onClose={vi.fn()} skill={skill} basePath="/projects/1/skills" />,
    );

    await userEvent.click(screen.getByRole('button', { name: /delete/i }));

    expect(router.delete).toHaveBeenCalledWith(
      '/projects/1/skills/7',
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('clicking Cancel calls onClose and does NOT delete', async () => {
    const onClose = vi.fn();
    renderPage(
      <DeleteSkillModal opened onClose={onClose} skill={skill} basePath="/projects/1/skills" />,
    );

    await userEvent.click(screen.getByRole('button', { name: /cancel/i }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(router.delete).not.toHaveBeenCalled();
  });
});
