import { describe, expect, it } from 'vitest';

import { mentionBlocker } from './mentions';

describe('mentionBlocker', () => {
  it('says nothing when the tracker recognises mentions', () => {
    expect(mentionBlocker({ provider: 'linear', mentionsRecognized: true })).toBeNull();
  });

  it('explains why a Linear API-key connection cannot recognise a mention', () => {
    expect(mentionBlocker({ provider: 'linear', mentionsRecognized: false })).toMatch(
      /This Linear account is kept for Aixle/,
    );
  });

  it('explains why a GitHub Projects tracker cannot recognise a mention', () => {
    expect(mentionBlocker({ provider: 'github', mentionsRecognized: false })).toMatch(/no GitHub App slug configured/);
  });
});
