import camelcaseKeysLib from 'camelcase-keys';
import decamelize from 'decamelize-keys';

/**
 * Regular expression to match keys with numbers and dashes (e.g., "9-12", "1-5-10")
 * These keys should be preserved as-is during camelCase conversion
 */
const NUMERIC_DASH_KEY_PATTERN = /^\d+(-\d+)+$/;

export const camelcaseKeys = (data: Record<string, unknown>) =>
  camelcaseKeysLib(data, {
    deep: true,
    exclude: [NUMERIC_DASH_KEY_PATTERN, 'headers'],
  });

export const decamelizeKeys = (data: Record<string, unknown>) =>
  decamelize(data, {
    deep: true,
    exclude: ['headers'],
  });
