// IANA timezone list from the runtime (falls back to UTC if unsupported).
export const IANA_TIMEZONES: string[] = (() => {
  try {
    const intl = Intl as typeof Intl & { supportedValuesOf?: (key: string) => string[] };
    return intl.supportedValuesOf?.('timeZone') ?? ['UTC'];
  } catch {
    return ['UTC'];
  }
})();

// Append the current UTC offset to a timezone, e.g. "Europe/Belgrade (UTC+02:00)".
export function tzLabel(tz: string): string {
  try {
    const raw =
      new Intl.DateTimeFormat('en-US', { timeZone: tz, timeZoneName: 'longOffset' })
        .formatToParts(new Date())
        .find((p) => p.type === 'timeZoneName')?.value ?? 'GMT';
    const offset = raw === 'GMT' ? 'UTC+00:00' : raw.replace('GMT', 'UTC');
    return `${tz} (${offset})`;
  } catch {
    return tz;
  }
}

export const TIMEZONE_OPTIONS = IANA_TIMEZONES.map((tz) => ({ value: tz, label: tzLabel(tz) }));
