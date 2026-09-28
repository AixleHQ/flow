import { describe, expect, it } from 'vitest';

import { clipboardKeyAction } from './clipboardKeys';

const key = (init: Partial<KeyboardEvent>) =>
  ({ key: '', code: '', ctrlKey: false, shiftKey: false, altKey: false, metaKey: false, ...init }) as KeyboardEvent;

const windows = { isMac: false, hasSelection: false };
const withSelection = { isMac: false, hasSelection: true };

describe('clipboardKeyAction', () => {
  it('copies on Ctrl+C only while something is selected, so ^C still interrupts', () => {
    expect(clipboardKeyAction(key({ key: 'c', code: 'KeyC', ctrlKey: true }), withSelection)).toBe('copy');
    expect(clipboardKeyAction(key({ key: 'c', code: 'KeyC', ctrlKey: true }), windows)).toBeNull();
  });

  it('copies on Ctrl+Shift+C and Ctrl+Insert', () => {
    expect(clipboardKeyAction(key({ key: 'C', code: 'KeyC', ctrlKey: true, shiftKey: true }), windows)).toBe('copy');
    expect(clipboardKeyAction(key({ key: 'Insert', ctrlKey: true }), withSelection)).toBe('copy');
  });

  it('pastes on Ctrl+V, Ctrl+Shift+V and Shift+Insert', () => {
    expect(clipboardKeyAction(key({ key: 'v', code: 'KeyV', ctrlKey: true }), windows)).toBe('paste');
    expect(clipboardKeyAction(key({ key: 'V', code: 'KeyV', ctrlKey: true, shiftKey: true }), windows)).toBe('paste');
    expect(clipboardKeyAction(key({ key: 'Insert', shiftKey: true }), windows)).toBe('paste');
  });

  it('follows the physical key on a non-Latin layout', () => {
    expect(clipboardKeyAction(key({ key: 'м', code: 'KeyV', ctrlKey: true }), windows)).toBe('paste');
    expect(clipboardKeyAction(key({ key: 'с', code: 'KeyC', ctrlKey: true }), withSelection)).toBe('copy');
  });

  it('leaves every key to the terminal on the Mac', () => {
    const mac = { isMac: true, hasSelection: true };
    expect(clipboardKeyAction(key({ key: 'c', code: 'KeyC', ctrlKey: true }), mac)).toBeNull();
    expect(clipboardKeyAction(key({ key: 'v', code: 'KeyV', ctrlKey: true }), mac)).toBeNull();
  });

  it('leaves other Ctrl keys to the CLI', () => {
    expect(clipboardKeyAction(key({ key: 'b', code: 'KeyB', ctrlKey: true }), withSelection)).toBeNull();
    expect(clipboardKeyAction(key({ key: 'v', code: 'KeyV', ctrlKey: true, altKey: true }), windows)).toBeNull();
  });
});
