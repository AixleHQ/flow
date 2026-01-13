import { BaseQueryFn, createApi } from '@reduxjs/toolkit/query/react';
import axios from 'axios';
import type { AxiosRequestConfig, AxiosError } from 'axios';
import qs from 'qs';

import { camelcaseKeys, decamelizeKeys } from './convertCase';
import { QueryTag } from './QueryTag';

// CSRF token extraction helper
function getCsrfToken(): string | null {
  const metaTag = document.querySelector('meta[name="csrf-token"]');
  return metaTag ? metaTag.getAttribute('content') : null;
}

const axiosInstance = axios.create({
  withCredentials: true,
  paramsSerializer: (params) => qs.stringify(params, { arrayFormat: 'brackets', encode: true }),
});

// Add CSRF token to all requests
axiosInstance.interceptors.request.use((config) => {
  const csrfToken = getCsrfToken();
  if (csrfToken) {
    config.headers = config.headers || {};
    config.headers['X-CSRF-Token'] = csrfToken;
  }
  return config;
});

const axiosBaseQuery =
  (
    { baseUrl }: { baseUrl: string } = { baseUrl: '' },
  ): BaseQueryFn<
    {
      url: string;
      method?: AxiosRequestConfig['method'];
      data?: AxiosRequestConfig['data'];
      params?: AxiosRequestConfig['params'];
      headers?: AxiosRequestConfig['headers'];
      isDecamelize?: boolean;
    },
    unknown,
    unknown
  > =>
  async ({ url, method, data, params, headers, isDecamelize = true }) => {
    try {
      const result = await axiosInstance({
        url: baseUrl + url,
        method,
        data: isDecamelize ? decamelizeKeys(data) : data,
        params: isDecamelize ? decamelizeKeys(params) : params,
        headers,
      });
      return {
        data: camelcaseKeys(result.data),
      };
    } catch (axiosError) {
      const err = axiosError as AxiosError;
      return {
        error: {
          status: err.response?.status,
          data: camelcaseKeys(err.response?.data as Record<string, unknown>) || err.message,
        },
      };
    }
  };

axiosInstance.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response.status === 401) {
      if (window.location.pathname !== '/login') {
        window.location.href = '/login';
      }
    }
    return Promise.reject(error);
  },
);

export const baseApi = createApi({
  baseQuery: axiosBaseQuery(),
  endpoints: () => ({}),
  tagTypes: Object.values(QueryTag),
});
