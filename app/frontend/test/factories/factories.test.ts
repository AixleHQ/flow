import { describe, expect, it } from 'vitest';

import { buildBoardTask } from './boardTask';
import { buildProject } from './project';

describe('typed factories', () => {
  it('buildProject applies overrides over typed defaults', () => {
    expect(buildProject().name).toBe('Acme');
    expect(buildProject({ name: 'X', state: 'archived' })).toMatchObject({
      name: 'X',
      state: 'archived',
      slug: 'acme',
    });
  });

  it('buildBoardTask applies overrides', () => {
    expect(buildBoardTask().title).toBe('Task');
    expect(buildBoardTask({ title: 'Bug', priority: 'high' }).priority).toBe('high');
  });
});
