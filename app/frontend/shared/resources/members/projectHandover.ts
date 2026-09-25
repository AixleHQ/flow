export interface HandoverProject {
  id: number;
  name: string;
  ownerId: number;
}

export interface HandoverCandidate {
  id: number;
  name: string | null;
  email: string;
  companyAdmin: boolean;
}

export interface ProjectHandover {
  projects: HandoverProject[];
  candidates: HandoverCandidate[];
  /** Company admins, most senior first — the server's default heir order. */
  heirIds: number[];
}

// A type alias, not an interface: Inertia's request data needs an index signature.
export type HandoverChoice = {
  projectId: number;
  userId: number;
};
