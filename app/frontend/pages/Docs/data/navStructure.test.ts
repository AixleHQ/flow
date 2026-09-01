import { describe, expect, it } from 'vitest';

import { findNavItem, findNavSection, getPrevNext } from './navStructure';

describe('findNavItem', () => {
  it('finds a top-level item by slug', () => {
    expect(findNavItem('agents')?.label).toBe('Agents');
  });

  it('returns null for an unknown slug', () => {
    expect(findNavItem('does-not-exist')).toBeNull();
  });
});

describe('findNavSection', () => {
  it('returns the section that contains the slug', () => {
    expect(findNavSection('api-guide')?.label).toBe('Reference');
    expect(findNavSection('agents')?.label).toBe('User guide');
    expect(findNavSection('changelog-product-areas')?.label).toBe('Product');
  });
});

describe('getPrevNext', () => {
  it('first item has no prev', () => {
    const { prev, next } = getPrevNext('user-guide');
    expect(prev).toBeNull();
    expect(next?.slug).toBe('quick-start');
  });

  it('last item has no next', () => {
    const { prev, next } = getPrevNext('changelog-product-areas');
    expect(next).toBeNull();
    expect(prev?.slug).toBe('user-guide-outline');
  });

  it('crosses a section boundary', () => {
    const { prev, next } = getPrevNext('config-schema');
    expect(prev?.slug).toBe('api-guide');
    expect(next?.slug).toBe('user-guide-outline');
  });

  it('a middle item has both neighbours', () => {
    const { prev, next } = getPrevNext('agents');
    expect(prev?.slug).toBe('quick-start');
    expect(next?.slug).toBe('runtimes');
  });
});
