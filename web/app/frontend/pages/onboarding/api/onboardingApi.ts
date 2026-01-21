import { baseApi, QueryTag } from 'shared/api';

import type { CompleteOnboardingRequest, CompleteOnboardingResponse, OnboardingResponse } from '../lib/types';

export const onboardingApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getOnboarding: builder.query<OnboardingResponse, void>({
      query: () => ({
        url: '/api/v1/onboarding',
        method: 'GET',
      }),
      providesTags: [QueryTag.Onboarding],
    }),
    completeOnboarding: builder.mutation<CompleteOnboardingResponse, CompleteOnboardingRequest>({
      query: (data) => ({
        url: '/api/v1/onboarding',
        method: 'POST',
        data,
      }),
      invalidatesTags: [QueryTag.CurrentUser, QueryTag.Onboarding],
    }),
  }),
});

export const { useGetOnboardingQuery, useCompleteOnboardingMutation } = onboardingApi;
