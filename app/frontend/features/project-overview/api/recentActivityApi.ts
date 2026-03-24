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
    getRecentActivity: builder.query<RecentActivityResponse, { projectId: number; page?: number; perPage?: number }>({
      query: ({ projectId, page, perPage }) => ({
        url: Routes.backend.apiV1CompanyProjectStatisticRecentActivityPath(projectId),
        method: 'GET',
        params: { page: page ?? 1, per_page: perPage ?? 20 },
      }),
      providesTags: [QueryTag.RecentActivity],
    }),
  }),
});

export const { useGetRecentActivityQuery } = recentActivityApi;
