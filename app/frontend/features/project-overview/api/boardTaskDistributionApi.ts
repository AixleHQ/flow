import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

export interface BoardColumnCount {
  name: string;
  count: number;
}

export interface BoardTaskDistribution {
  columns: BoardColumnCount[];
  total: number;
}

export const boardTaskDistributionApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getBoardTaskDistribution: builder.query<BoardTaskDistribution, void>({
      query: () => ({
        url: Routes.backend.apiV1CompanyStatisticBoardTaskDistributionPath(),
        method: 'GET',
      }),
      providesTags: [QueryTag.BoardTaskDistribution],
    }),
  }),
});

export const { useGetBoardTaskDistributionQuery } = boardTaskDistributionApi;
