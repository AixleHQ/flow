import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import type { ProjectHandover } from './projectHandover';
import { ProjectHandoverModal } from './ProjectHandoverModal';

const handover: ProjectHandover = {
  projects: [
    { id: 10, name: 'Gateway', ownerId: 7 },
    { id: 11, name: 'Billing', ownerId: 7 },
    { id: 12, name: 'Someone else’s', ownerId: 9 },
  ],
  candidates: [
    { id: 7, name: 'Ada Leaving', email: 'ada@example.com', companyAdmin: true },
    { id: 8, name: 'Grace Admin', email: 'grace@example.com', companyAdmin: true },
    { id: 9, name: 'Bo Employee', email: 'bo@example.com', companyAdmin: false },
  ],
  heirIds: [7, 8],
};

const renderModal = (over: Partial<ProjectHandover> = {}) => {
  const onConfirm = vi.fn();
  renderPage(
    <ProjectHandoverModal
      title="Remove member"
      intro={<p>Remove Ada?</p>}
      confirmLabel="Transfer and remove"
      subject="They"
      leavingUserId={7}
      handover={{ ...handover, ...over }}
      onConfirm={onConfirm}
      onClose={vi.fn()}
    />,
  );
  return { onConfirm };
};

describe('ProjectHandoverModal', () => {
  it('lists only the leaving member’s projects, each preset to the most senior other admin', async () => {
    const { onConfirm } = renderModal();

    expect(screen.getByText('They own 2 projects here. Choose who takes each one over first.')).toBeInTheDocument();
    expect(screen.queryByText('Someone else’s')).not.toBeInTheDocument();
    expect(screen.getAllByDisplayValue('Grace Admin (grace@example.com)')).toHaveLength(2);

    await userEvent.click(screen.getByRole('button', { name: 'Transfer and remove' }));

    expect(onConfirm).toHaveBeenCalledWith([
      { projectId: 10, userId: 8 },
      { projectId: 11, userId: 8 },
    ]);
  });

  it('waits for a choice on every project when there is no admin to preset', () => {
    const { onConfirm } = renderModal({ heirIds: [7] });

    expect(screen.queryByDisplayValue(/grace@example.com/)).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Transfer and remove' })).toBeDisabled();
    expect(onConfirm).not.toHaveBeenCalled();
  });
});
