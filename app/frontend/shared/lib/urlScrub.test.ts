import { describe, expect, it } from 'vitest';

import { isTokenPath, scrubUrl } from './urlScrub';

const forAnalytics = (url: string) => scrubUrl(url, { placeholder: ':token', dropSecrets: true });

describe('scrubUrl for product analytics', () => {
  it.each([
    ['https://flow.example.com/login/magic/abc.def-1', 'https://flow.example.com/login/magic/:token'],
    ['/invitations/abc123', '/invitations/:token'],
    ['/invitations/abc123/accept', '/invitations/:token/accept'],
    ['/password/reset/r3set', '/password/reset/:token'],
    ['/share/s3cr3t', '/share/:token'],
    ['/share/s3cr3t/raw', '/share/:token/raw'],
  ])('replaces the token in %s', (url, expected) => {
    expect(forAnalytics(url)).toBe(expected);
  });

  it('drops the workspace confirmation token and every credential-bearing parameter, keeping the rest', () => {
    expect(forAnalytics('/workspace/confirm?token=t0k&email=dana%40acme.test')).toBe('/workspace/confirm');
    expect(forAnalytics('/oauth/callback?code=c&state=s&keep=1')).toBe('/oauth/callback?keep=1');
  });

  it('leaves ordinary URLs and the token-less reset form alone', () => {
    expect(forAnalytics('/company/projects/12/board?n=4')).toBe('/company/projects/12/board?n=4');
    expect(forAnalytics('/password/reset')).toBe('/password/reset');
  });
});

describe('isTokenPath', () => {
  it('knows which pages carry a credential in their URL', () => {
    expect(isTokenPath('/login/magic/abc')).toBe(true);
    expect(isTokenPath('/invitations/abc')).toBe(true);
    expect(isTokenPath('/password/reset/abc')).toBe(true);
    expect(isTokenPath('/share/abc')).toBe(true);
    expect(isTokenPath('/password/reset')).toBe(false);
    expect(isTokenPath('/company/projects')).toBe(false);
  });
});
