import { Path, UseFormSetError } from 'react-hook-form';

import { ApiError } from './types';

export const setErrorsToForm = <T extends Record<string, unknown>>(
  error: unknown,
  setError: UseFormSetError<T>,
): string | null => {
  const apiError = error as ApiError<T>;

  if (apiError.data?.errors) {
    Object.entries(apiError.data.errors).forEach(([field, messages]) => {
      if (messages && messages.length > 0) {
        setError(field as Path<T>, { message: messages[0] });
      }
    });
  }

  return apiError.data?.message || null;
};
