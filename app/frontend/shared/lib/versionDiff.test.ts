import { describe, expect, it } from 'vitest';

import { MAX_DIFF_LINES, diffLines, diffSnapshots } from './versionDiff';
import { VERSION_SCHEMAS } from './versionSchemas';

describe('diffLines', () => {
  it('keeps common lines and marks the rest added or removed', () => {
    expect(diffLines('a\nb\nc', 'a\nx\nc')).toEqual([
      { type: 'same', text: 'a' },
      { type: 'removed', text: 'b' },
      { type: 'added', text: 'x' },
      { type: 'same', text: 'c' },
    ]);
  });

  it('gives up on text too long to diff', () => {
    const long = Array.from({ length: MAX_DIFF_LINES + 1 }, (_, i) => `line ${i}`).join('\n');
    expect(diffLines(long, 'short')).toBeNull();
  });
});

describe('diffSnapshots', () => {
  it('reports only the agent fields that changed', () => {
    const changes = diffSnapshots(
      VERSION_SCHEMAS.Agent,
      { name: 'coder', title: 'Coder', persona: 'writes code' },
      { name: 'coder', title: 'Senior Coder', persona: 'writes code\nreviews code' },
    );

    expect(changes).toEqual([
      { kind: 'scalar', label: 'Title', before: 'Coder', after: 'Senior Coder' },
      {
        kind: 'text',
        label: 'Persona',
        lines: [
          { type: 'same', text: 'writes code' },
          { type: 'added', text: 'reviews code' },
        ],
      },
    ]);
  });

  it('diffs a first version against an empty entity', () => {
    const changes = diffSnapshots(VERSION_SCHEMAS.Agent, null, { title: 'New' });
    expect(changes).toEqual([{ kind: 'scalar', label: 'Title', before: undefined, after: 'New' }]);
  });

  it('lists skill files added, removed and changed, with a line diff for the changed one', () => {
    const changes = diffSnapshots(
      VERSION_SCHEMAS.Skill,
      { files: { 'SKILL.md': 'one', 'scripts/old.sh': 'x' } },
      { files: { 'SKILL.md': 'two', 'scripts/new.sh': 'y' } },
    );

    expect(changes).toEqual([
      {
        kind: 'entries',
        label: 'Files',
        entries: [
          {
            name: 'SKILL.md',
            status: 'changed',
            lines: [
              { type: 'removed', text: 'one' },
              { type: 'added', text: 'two' },
            ],
          },
          { name: 'scripts/new.sh', status: 'added' },
          { name: 'scripts/old.sh', status: 'removed' },
        ],
      },
    ]);
  });

  it('says a secret changed without ever showing a value', () => {
    const changes = diffSnapshots(
      VERSION_SCHEMAS.MCPServer,
      { secrets: { headers: { Authorization: 'hmac:aaa' }, env: {} } },
      { secrets: { headers: { Authorization: 'hmac:bbb' }, env: { API_KEY: 'hmac:ccc' } } },
    );

    expect(changes).toEqual([
      { kind: 'entries', label: 'Headers', entries: [{ name: 'Authorization', status: 'changed' }] },
      { kind: 'entries', label: 'Environment variables', entries: [{ name: 'API_KEY', status: 'added' }] },
    ]);
  });

  it('names workflow references, flags archived and deleted ones, and follows steps by id', () => {
    const before = {
      name: 'Release',
      config: { base_tool_ids: [1] },
      steps: [
        { id: 10, name: 'Build', instructions: 'make', tool_ids: [], depends_on_step_ids: [], sub_steps: [] },
        { id: 11, name: 'Test', depends_on_step_ids: [10], sub_steps: [{ id: 5, name: 'lint' }] },
      ],
    };
    const after = {
      name: 'Release',
      config: { base_tool_ids: [2] },
      steps: [
        { id: 11, name: 'Test', depends_on_step_ids: [], sub_steps: [] },
        { id: 12, name: 'Deploy', depends_on_step_ids: [11], sub_steps: [] },
      ],
    };
    const references = { Tool: { '1': { name: 'Linter', archived: true } } };

    const changes = diffSnapshots(VERSION_SCHEMAS.Workflow, before, after, references);

    expect(changes[0]).toEqual({
      kind: 'refs',
      label: 'Workflow tools',
      added: [{ id: '2', name: '#2', archived: false, missing: true }],
      removed: [{ id: '1', name: 'Linter', archived: true, missing: false }],
    });
    expect(changes[1]).toMatchObject({
      kind: 'collection',
      label: 'Steps',
      items: [
        {
          label: 'Test',
          status: 'changed',
          changes: [
            { kind: 'refs', label: 'Depends on', removed: [{ name: 'Build' }] },
            { kind: 'collection', label: 'Sub-steps', items: [{ label: 'lint', status: 'removed' }] },
          ],
        },
        { label: 'Deploy', status: 'added' },
        { label: 'Build', status: 'removed' },
      ],
    });
  });

  it('reports a step that only moved', () => {
    const a = { id: 1, name: 'A', sub_steps: [] };
    const b = { id: 2, name: 'B', sub_steps: [] };
    const changes = diffSnapshots(VERSION_SCHEMAS.Workflow, { steps: [a, b] }, { steps: [b, a] });

    expect(changes).toEqual([
      {
        kind: 'collection',
        label: 'Steps',
        items: [
          { label: 'B', status: 'moved', changes: [] },
          { label: 'A', status: 'moved', changes: [] },
        ],
      },
    ]);
  });

  it('finds nothing to report between equal snapshots', () => {
    const snapshot = { name: 'x', steps: [{ id: 1, name: 'A', sub_steps: [] }] };
    expect(diffSnapshots(VERSION_SCHEMAS.Workflow, snapshot, structuredClone(snapshot))).toEqual([]);
  });
});
