import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

import type { Skill, CreateSkillRequest, UpdateSkillRequest } from '../lib/types';

interface SkillsResponse {
  items: Skill[];
}

export const skillsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    // Company-level skills
    getCompanySkills: builder.query<Skill[], void>({
      query: () => ({
        url: Routes.backend.apiV1CompanySkillsPath(),
        method: 'GET',
      }),
      transformResponse: (response: Skill[] | SkillsResponse) => {
        return Array.isArray(response) ? response : response.items;
      },
      providesTags: [QueryTag.Skills],
    }),

    // Project-level skills (merged list)
    getProjectSkills: builder.query<Skill[], number>({
      query: (projectId) => ({
        url: Routes.backend.apiV1CompanyProjectSkillsPath(projectId),
        method: 'GET',
      }),
      transformResponse: (response: Skill[] | SkillsResponse) => {
        return Array.isArray(response) ? response : response.items;
      },
      providesTags: [QueryTag.Skills],
    }),

    // Create skill (company or project level)
    createCompanySkill: builder.mutation<Skill, CreateSkillRequest>({
      query: (data) => ({
        url: Routes.backend.apiV1CompanySkillsPath(),
        method: 'POST',
        data: { skill: data },
      }),
      invalidatesTags: [QueryTag.Skills],
    }),

    createProjectSkill: builder.mutation<Skill, { projectId: number } & CreateSkillRequest>({
      query: ({ projectId, ...data }) => ({
        url: Routes.backend.apiV1CompanyProjectSkillsPath(projectId),
        method: 'POST',
        data: { skill: data },
      }),
      invalidatesTags: [QueryTag.Skills],
    }),

    // Update skill
    updateCompanySkill: builder.mutation<Skill, UpdateSkillRequest>({
      query: ({ id, ...data }) => ({
        url: Routes.backend.apiV1CompanySkillPath(id),
        method: 'PATCH',
        data: { skill: data },
      }),
      invalidatesTags: [QueryTag.Skills],
    }),

    updateProjectSkill: builder.mutation<Skill, { projectId: number } & UpdateSkillRequest>({
      query: ({ projectId, id, ...data }) => ({
        url: Routes.backend.apiV1CompanyProjectSkillPath(projectId, id),
        method: 'PATCH',
        data: { skill: data },
      }),
      invalidatesTags: [QueryTag.Skills],
    }),

    // Delete skill
    deleteCompanySkill: builder.mutation<void, number>({
      query: (id) => ({
        url: Routes.backend.apiV1CompanySkillPath(id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Skills],
    }),

    deleteProjectSkill: builder.mutation<void, { projectId: number; id: number }>({
      query: ({ projectId, id }) => ({
        url: Routes.backend.apiV1CompanyProjectSkillPath(projectId, id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Skills],
    }),
  }),
});

export const {
  useGetCompanySkillsQuery,
  useGetProjectSkillsQuery,
  useCreateCompanySkillMutation,
  useCreateProjectSkillMutation,
  useUpdateCompanySkillMutation,
  useUpdateProjectSkillMutation,
  useDeleteCompanySkillMutation,
  useDeleteProjectSkillMutation,
} = skillsApi;
