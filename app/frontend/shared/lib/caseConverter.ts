/**
 * Utility functions to convert between snake_case and camelCase using libraries
 * This approach leverages well-tested libraries instead of custom implementations
 */

import camelcaseKeys from 'camelcase-keys';
import decamelizeKeys from 'decamelize-keys';

/**
 * Recursively transforms object keys from snake_case to camelCase
 */
export const keysToCamelCase = (data: Record<string, unknown>) => camelcaseKeys(data, { deep: true });

/**
 * Recursively transforms object keys from camelCase to snake_case
 */
export const keysToSnakeCase = (data: Record<string, unknown>) => decamelizeKeys(data, { deep: true });

export default {
  keysToCamelCase,
  keysToSnakeCase,
};
