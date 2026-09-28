import { describe, expect, it } from 'vitest';

import { ideThemeUrl, ideUrlWithScheme } from './ideTheme';

const IDE_URL =
  'http://sandbox.test/t/abc/fs/preload?to=http%3A%2F%2Fsandbox.test%2Ft%2Fabc%2Fide%2F&aixle_ticket=pass';

describe('ideUrlWithScheme', () => {
  it('asks the preload page to open the IDE in the theme', () => {
    const url = new URL(ideUrlWithScheme(IDE_URL, 'light'));

    expect(url.searchParams.get('scheme')).toBe('light');
    expect(url.searchParams.get('to')).toBe('http://sandbox.test/t/abc/ide/');
    expect(url.searchParams.get('aixle_ticket')).toBe('pass');
  });
});

describe('ideThemeUrl', () => {
  it('points at the theme page of the same container, pass kept', () => {
    const url = new URL(ideThemeUrl(IDE_URL, 'dark')!);

    expect(url.pathname).toBe('/t/abc/fs/theme');
    expect(url.searchParams.get('scheme')).toBe('dark');
    expect(url.searchParams.get('aixle_ticket')).toBe('pass');
    expect(url.searchParams.has('to')).toBe(false);
  });

  it('has nothing to offer for a URL that is not the preload page', () => {
    expect(ideThemeUrl('http://sandbox.test/t/abc/ide/', 'dark')).toBeNull();
  });
});
