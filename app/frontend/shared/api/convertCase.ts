import camelcaseKeysLib from 'camelcase-keys';
import decamelize from 'decamelize-keys';

/**
 * Regular expression to match keys with numbers and dashes (e.g., "9-12", "1-5-10")
 * These keys should be preserved as-is during camelCase conversion
 */
const NUMERIC_DASH_KEY_PATTERN = /^\d+(-\d+)+$/;

/**
 * Keys whose **values** must be preserved as-is during case conversion.
 * `exclude` in camelcase-keys only prevents renaming the key itself — it does
 * NOT stop deep recursion into the value.  We solve this by replacing values
 * with `null` before conversion and restoring originals after.
 */
const PRESERVED_VALUE_KEYS = new Set(['headers']);

/* eslint-disable @typescript-eslint/no-explicit-any */

/** Replace values of PRESERVED_VALUE_KEYS with null, saving originals in order. */
function stripPreserved(obj: any, originals: unknown[]): any {
  if (obj === null || obj === undefined || typeof obj !== 'object') return obj;
  if (Array.isArray(obj)) return obj.map((item) => stripPreserved(item, originals));

  const result: Record<string, any> = {};
  for (const [key, value] of Object.entries(obj)) {
    if (PRESERVED_VALUE_KEYS.has(key) && value && typeof value === 'object' && !Array.isArray(value)) {
      originals.push(value);
      result[key] = null;
    } else {
      result[key] = stripPreserved(value, originals);
    }
  }
  return result;
}

/** Restore null placeholders with original values (same depth-first order). */
function restorePreserved(obj: any, originals: unknown[], idx: { v: number }): any {
  if (obj === null || obj === undefined || typeof obj !== 'object') return obj;
  if (Array.isArray(obj)) return obj.map((item) => restorePreserved(item, originals, idx));

  const result: Record<string, any> = {};
  for (const [key, value] of Object.entries(obj)) {
    if (PRESERVED_VALUE_KEYS.has(key) && value === null) {
      result[key] = originals[idx.v++];
    } else {
      result[key] = restorePreserved(value, originals, idx);
    }
  }
  return result;
}

/* eslint-enable @typescript-eslint/no-explicit-any */

export const camelcaseKeys = (data: Record<string, unknown>) => {
  const originals: unknown[] = [];
  const stripped = stripPreserved(data, originals);
  const converted = camelcaseKeysLib(stripped, {
    deep: true,
    exclude: [NUMERIC_DASH_KEY_PATTERN, ...PRESERVED_VALUE_KEYS],
  });
  return originals.length > 0 ? restorePreserved(converted, originals, { v: 0 }) : converted;
};

export const decamelizeKeys = (data: Record<string, unknown>) => {
  const originals: unknown[] = [];
  const stripped = stripPreserved(data, originals);
  const converted = decamelize(stripped, {
    deep: true,
    exclude: [...PRESERVED_VALUE_KEYS],
  });
  return originals.length > 0 ? restorePreserved(converted, originals, { v: 0 }) : converted;
};
