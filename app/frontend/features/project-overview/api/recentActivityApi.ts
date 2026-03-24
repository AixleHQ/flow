import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

export interface ActivityItem {
  eventType: string;
  description: string;
  actorName: string;
  actorType: string;
  occurredAt: string;
}

export interface RecentActivityMeta {
  total: number;
  page: number;
  perPage: number;
}

export interface RecentActivityResponse {
  activities: ActivityItem[];
  meta: RecentActivityMeta;
}

export const recentActivityApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getRecentActivity: builder.query<RecentActivityResponse, { page?: number; perPage?: number } | void>({
      query: (params) => ({
        url: Routes.backend.apiV1CompanyStatisticRecentActivityPath(),
        method: 'GET',
        params: params ? { page: params.page ?? 1, per_page: params.perPage ?? 20 } : { page: 1, per_page: 20 },
      }),
      providesTags: [QueryTag.RecentActivity],
    }),
  }),
});

export const { useGetRecentActivityQuery } = recentActivityApi;
