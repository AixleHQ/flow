export type UserRole = 'employee' | 'admin';
export type UserState = 'active' | 'pending' | 'archived' | 'suspended';

export interface CompanyUserBrief {
  id: number;
  name: string;
}

export interface CompanyUser {
  id: number;
  email: string;
  name: string;
  role: UserRole;
  state: UserState;
  position: string | null;
  invitedAt: string | null;
  invitedBy: CompanyUserBrief | null;
  createdAt: string;
  updatedAt: string;
}

export interface CompanyUsersFilters {
  page?: number;
  perPage?: number;
  role?: UserRole;
  state?: UserState;
  search?: string;
}

export interface CreateCompanyUserRequest {
  email: string;
  name: string;
  role: UserRole;
}

export interface UpdateCompanyUserRequest {
  id: number;
  role?: UserRole;
  stateEvent?: 'activate' | 'archive' | 'suspend';
}
