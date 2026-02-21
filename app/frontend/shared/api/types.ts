export interface ApiResponse<T = unknown> {
  data: T;
  items?: T[];
  meta?: {
    page: number;
    perPage: number;
    totalPages: number;
    totalCount: number;
  };
}

interface Meta {
  page: number;
  perPage: number;
  totalPages: number;
  totalCount: number;
}

export interface ApiCollectionResponse<T = unknown> {
  items: T[];
  meta: Meta;
}

// Alias for paginated API responses
export type PaginatedResponse<T> = ApiCollectionResponse<T>;

export interface ApiError<T = unknown> {
  data?: {
    message: string;
    errors?: Partial<Record<keyof T, string[]>>;
  };
  status?: number;
}
