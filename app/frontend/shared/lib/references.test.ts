import { describe, expect, it } from 'vitest';

import { brokenReferenceLabel, referenceToken, renameOutputReferences, scanReferences } from './references';

describe('scanReferences', () => {
  it('finds every token with its position and parsed body', () => {
    const text = 'Read {{asset:12}}, ask {{mcp:7}}, after {{step:new-3}} write {{output:45:reports/q3 summary.md}}.';

    expect(scanReferences(text)).toEqual([
      { kind: 'asset', token: '{{asset:12}}', from: 5, to: 17, valid: true, id: 12 },
      { kind: 'mcp', token: '{{mcp:7}}', from: 23, to: 32, valid: true, id: 7 },
      { kind: 'step', token: '{{step:new-3}}', from: 40, to: 54, valid: true, stepRef: 'new-3' },
      {
        kind: 'output',
        token: '{{output:45:reports/q3 summary.md}}',
        from: 61,
        to: 96,
        valid: true,
        stepRef: '45',
        name: 'reports/q3 summary.md',
      },
    ]);
  });

  it('keeps a token with a body that does not parse, marked invalid', () => {
    const refs = scanReferences('{{asset:abc}} {{step:0}} {{output:4}} {{output:4:}} {{mcp:-1}}');

    expect(refs.map((r) => [r.token, r.valid])).toEqual([
      ['{{asset:abc}}', false],
      ['{{step:0}}', false],
      ['{{output:4}}', false],
      ['{{output:4:}}', false],
      ['{{mcp:-1}}', false],
    ]);
  });

  it('leaves other braces and unknown prefixes as text', () => {
    expect(scanReferences('{{artifact_name}} {{inputs.repo}} {{agent:3}} {{asset:1\n}}')).toEqual([]);
  });

  it('reads skill, tool and config item tokens by id', () => {
    expect(scanReferences('{{skill:4}} {{tool:5}} {{config_item:6}} {{config_item:STAGING}}')).toEqual([
      { kind: 'skill', token: '{{skill:4}}', from: 0, to: 11, valid: true, id: 4 },
      { kind: 'tool', token: '{{tool:5}}', from: 12, to: 22, valid: true, id: 5 },
      { kind: 'config_item', token: '{{config_item:6}}', from: 23, to: 40, valid: true, id: 6 },
      { kind: 'config_item', token: '{{config_item:STAGING}}', from: 41, to: 64, valid: false },
    ]);
    expect(referenceToken.configItem(6)).toBe('{{config_item:6}}');
  });

  it('splits an output body at the first colon, so names may contain one', () => {
    expect(scanReferences('{{output:9:a:b.md}}')[0]).toMatchObject({ stepRef: '9', name: 'a:b.md' });
  });
});

describe('brokenReferenceLabel', () => {
  it('names what the token meant to point at', () => {
    const [asset, mcp, step, output, bad] = scanReferences(
      '{{asset:12}} {{mcp:7}} {{step:3}} {{output:3:x.md}} {{asset:x}}',
    );

    expect(brokenReferenceLabel(asset)).toBe('Missing asset #12');
    expect(brokenReferenceLabel(mcp)).toBe('Missing MCP server #7');
    expect(brokenReferenceLabel(step)).toBe('Missing session');
    expect(brokenReferenceLabel(output)).toBe('Undeclared output x.md');
    expect(brokenReferenceLabel(bad)).toBe('Invalid reference');
  });

  it('names a missing skill, tool and config item by id', () => {
    const [skill, tool, configItem] = scanReferences('{{skill:4}} {{tool:5}} {{config_item:6}}');

    expect(brokenReferenceLabel(skill)).toBe('Missing skill #4');
    expect(brokenReferenceLabel(tool)).toBe('Missing tool #5');
    expect(brokenReferenceLabel(configItem)).toBe('Missing config item #6');
  });
});

describe('renameOutputReferences', () => {
  it('rewrites only the renamed output of that step, every time it appears', () => {
    const text = [
      referenceToken.output('4', 'a.md'),
      referenceToken.output('4', 'a.md'),
      referenceToken.output('5', 'a.md'),
      referenceToken.output('4', 'b.md'),
    ].join(' ');

    expect(renameOutputReferences(text, '4', 'a.md', 'final.md')).toBe(
      '{{output:4:final.md}} {{output:4:final.md}} {{output:5:a.md}} {{output:4:b.md}}',
    );
  });
});
