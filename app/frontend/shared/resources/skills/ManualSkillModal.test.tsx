import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, within } from 'test/renderPage';

import { ManualSkillModal } from './ManualSkillModal';

const baseProps = {
  opened: true,
  onClose: vi.fn(),
  basePath: '/company/projects/1/skills',
};

const editedSkill = {
  id: 3,
  name: 'release-notes',
  content: '---\nname: release-notes\n---\n',
  currentVersionNumber: 2,
};

const discardDialog = () => screen.findByRole('dialog', { name: 'Discard unsaved changes?' });

describe('ManualSkillModal', () => {
  // The form IS the file: a skill is a SKILL.md, and its name has to come from the
  // frontmatter because the spec requires name and directory to match.
  it('starts from a SKILL.md template with the required frontmatter', () => {
    renderPage(<ManualSkillModal {...baseProps} />);

    const textarea = screen.getByLabelText('SKILL.md content') as HTMLTextAreaElement;

    expect(textarea.value).toContain('name: my-skill');
    expect(textarea.value).toContain('description:');
  });

  it('submits the pasted content to the manual endpoint', async () => {
    renderPage(<ManualSkillModal {...baseProps} />);

    await userEvent.click(screen.getByRole('button', { name: 'Add skill' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/1/skills/manual',
      expect.objectContaining({ content: expect.stringContaining('name: my-skill') }),
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('refuses to submit an empty file', async () => {
    renderPage(<ManualSkillModal {...baseProps} />);

    await userEvent.clear(screen.getByLabelText('SKILL.md content'));

    expect(screen.getByRole('button', { name: 'Add skill' })).toBeDisabled();
    expect(router.post).not.toHaveBeenCalled();
  });

  // Manual skills bypass the skills CLI entirely, so nothing about them is reported
  // upstream — the form says so, because that is the reason the path exists.
  it('states that the skill never leaves the deployment', () => {
    renderPage(<ManualSkillModal {...baseProps} />);

    expect(screen.getByText(/nothing about it is sent to skills.sh/i)).toBeInTheDocument();
  });

  // A rejected SKILL.md must never cost the user their draft. The server answers a
  // bad file with Inertia errors, which arrive through onError.
  it('keeps the pasted draft and shows the error when the server rejects it', async () => {
    const post = vi.mocked(router.post);
    post.mockImplementation((_url, _data, options) => {
      options?.onError?.({ content: 'name must use lowercase letters' });
      options?.onFinish?.({} as never);
    });

    renderPage(<ManualSkillModal {...baseProps} />);

    const textarea = screen.getByLabelText('SKILL.md content') as HTMLTextAreaElement;
    await userEvent.clear(textarea);
    await userEvent.type(textarea, 'my precious draft');
    await userEvent.click(screen.getByRole('button', { name: 'Add skill' }));

    expect(screen.getByText('name must use lowercase letters')).toBeInTheDocument();
    expect((screen.getByLabelText('SKILL.md content') as HTMLTextAreaElement).value).toBe('my precious draft');
    expect(baseProps.onClose).not.toHaveBeenCalled();
  });

  it('asks before closing a new skill the user has started writing, and closes on Discard', async () => {
    const onClose = vi.fn();
    renderPage(<ManualSkillModal {...baseProps} onClose={onClose} />);

    await userEvent.type(screen.getByRole('textbox', { name: 'SKILL.md content' }), 'More steps.');
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    const discard = await discardDialog();
    expect(screen.getByRole('dialog', { name: 'Add a skill by hand' })).toBeInTheDocument();
    expect(onClose).not.toHaveBeenCalled();

    await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('closes an untouched new skill without asking', async () => {
    const onClose = vi.fn();
    renderPage(<ManualSkillModal {...baseProps} onClose={onClose} />);

    await userEvent.click(
      within(screen.getByRole('dialog', { name: 'Add a skill by hand' })).getByRole('button', { name: 'Clear' }),
    );

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });

  it('asks before closing over an edited skill', async () => {
    const onClose = vi.fn();
    renderPage(<ManualSkillModal {...baseProps} onClose={onClose} skill={editedSkill} />);

    await userEvent.type(screen.getByRole('textbox', { name: 'SKILL.md content' }), 'Use it for changelogs.');
    await userEvent.click(
      within(screen.getByRole('dialog', { name: 'Edit release-notes' })).getByRole('button', { name: 'Clear' }),
    );

    const discard = await discardDialog();
    expect(onClose).not.toHaveBeenCalled();

    await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('closes an untouched edit without asking', async () => {
    const onClose = vi.fn();
    renderPage(<ManualSkillModal {...baseProps} onClose={onClose} skill={editedSkill} />);

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });
});
