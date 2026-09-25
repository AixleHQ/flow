export interface OwnershipCandidate {
  id: number;
  name: string | null;
  email: string;
  companyAdmin: boolean;
  collaborator: boolean;
}

export interface Ownership {
  canTransfer: boolean;
  candidates: OwnershipCandidate[];
}

// A bundle deployed ahead of its API pod renders props that have no `ownership` yet.
export const NO_OWNERSHIP_TRANSFER: Ownership = { canTransfer: false, candidates: [] };
