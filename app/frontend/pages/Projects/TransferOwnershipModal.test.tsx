import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import type { OwnershipCandidate } from './ownership';
import { TransferOwnershipModal } from './TransferOwnershipModal';

const collaborator: OwnershipCandidate = {
  id: 2,
  name: 'Bo Collab',
  email: 'bo@apollo.test',
  companyAdmin: false,
  collaborator: true,
};
const newcomer: OwnershipCandidate = {
  id: 3,
  name: 'Cy Admin',
  email: 'cy@apollo.test',
  companyAdmin: true,
  collaborator: false,
};

const renderModal = (overrides: Partial<Parameters<typeof TransferOwnershipModal>[0]> = {}) => {
  const onClose = vi.fn();
  renderPage(
    <TransferOwnershipModal
      onClose={onClose}
      projectId={7}
      projectName="Apollo Project"
      ownerName="Ada Owner"
      candidates={[collaborator, newcomer]}
      {...overrides}
    />,
  );
  return { onClose };
};

afterEach(() => {
  vi.clearAllMocks();
});

describe('Projects/TransferOwnershipModal', () => {
  it('groups candidates and keeps Continue disabled until one is picked', async () => {
    renderModal();

    expect(screen.getByText('On this project')).toBeInTheDocument();
    expect(screen.getByText('Company members')).toBeInTheDocument();
    const next = screen.getByRole('button', { name: 'Continue' });
    expect(next).toBeDisabled();

    await userEvent.click(screen.getByRole('radio', { name: 'Bo Collab' }));

    expect(next).toBeEnabled();
  });

  it('filters candidates by name or email', async () => {
    renderModal();

    await userEvent.type(screen.getByRole('textbox', { name: 'Search members' }), 'cy@');

    expect(screen.queryByRole('radio', { name: 'Bo Collab' })).not.toBeInTheDocument();
    expect(screen.getByRole('radio', { name: 'Cy Admin' })).toBeInTheDocument();
  });

  it('says so when nothing matches the search', async () => {
    renderModal();

    await userEvent.type(screen.getByRole('textbox', { name: 'Search members' }), 'zzz');

    expect(screen.getByText('No eligible members match “zzz”.')).toBeInTheDocument();
  });

  it('confirms before transferring, naming the new owner and the consequences', async () => {
    const { onClose } = renderModal();

    await userEvent.click(screen.getByRole('radio', { name: 'Cy Admin' }));
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }));

    expect(router.patch).not.toHaveBeenCalled();
    expect(screen.getByText('Transfer ownership?')).toBeInTheDocument();
    expect(screen.getByText(/becomes the owner of this project/)).toHaveTextContent('Cy Admin');
    expect(screen.getByText(/is not on this project yet/)).toBeInTheDocument();
    expect(screen.getByText(/stays on the project as a collaborator/)).toHaveTextContent('Ada Owner');

    await userEvent.click(screen.getByRole('button', { name: 'Transfer ownership' }));

    expect(router.patch).toHaveBeenCalledWith(
      '/company/projects/7/ownership',
      { ownership: { userId: 3 } },
      expect.objectContaining({ preserveScroll: true }),
    );
    const [, , options] = vi.mocked(router.patch).mock.calls[0];
    options?.onSuccess?.({} as never);
    expect(onClose).toHaveBeenCalled();
  });

  it('opens straight on the confirmation for a preselected member and offers Cancel, not Back', async () => {
    const { onClose } = renderModal({ targetId: collaborator.id });

    expect(screen.getByText('Transfer ownership?')).toBeInTheDocument();
    expect(screen.queryByText(/is not on this project yet/)).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Back' })).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(onClose).toHaveBeenCalled();
    expect(router.patch).not.toHaveBeenCalled();
  });
});
