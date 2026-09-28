import { describe, expect, it } from 'vitest';

import { isMacPlatform, terminalKeyAction } from './terminalKeys';

const key = (init: Partial<KeyboardEvent>) =>
  ({ key: '', code: '', ctrlKey: false, shiftKey: false, altKey: false, metaKey: false, ...init }) as KeyboardEvent;

const windows = { isMac: false, hasSelection: false };
const withSelection = { isMac: false, hasSelection: true };

describe('terminalKeyAction', () => {
  it('copies on Ctrl+C only while something is selected, so ^C still interrupts', () => {
    expect(terminalKeyAction(key({ key: 'c', code: 'KeyC', ctrlKey: true }), withSelection)).toEqual({ type: 'copy' });
    expect(terminalKeyAction(key({ key: 'c', code: 'KeyC', ctrlKey: true }), windows)).toBeNull();
  });

  it('copies on Ctrl+Shift+C and Ctrl+Insert', () => {
    expect(terminalKeyAction(key({ key: 'C', code: 'KeyC', ctrlKey: true, shiftKey: true }), windows)).toEqual({
      type: 'copy',
    });
    expect(terminalKeyAction(key({ key: 'Insert', ctrlKey: true }), withSelection)).toEqual({ type: 'copy' });
  });

  it('pastes on Ctrl+V, Ctrl+Shift+V and Shift+Insert', () => {
    expect(terminalKeyAction(key({ key: 'v', code: 'KeyV', ctrlKey: true }), windows)).toEqual({ type: 'paste' });
    expect(terminalKeyAction(key({ key: 'V', code: 'KeyV', ctrlKey: true, shiftKey: true }), windows)).toEqual({
      type: 'paste',
    });
    expect(terminalKeyAction(key({ key: 'Insert', shiftKey: true }), windows)).toEqual({ type: 'paste' });
  });

  it('follows the physical key on a non-Latin layout', () => {
    expect(terminalKeyAction(key({ key: 'м', code: 'KeyV', ctrlKey: true }), windows)).toEqual({ type: 'paste' });
    expect(terminalKeyAction(key({ key: 'с', code: 'KeyC', ctrlKey: true }), withSelection)).toEqual({ type: 'copy' });
  });

  it('leaves the clipboard keys to the terminal on the Mac', () => {
    const mac = { isMac: true, hasSelection: true };
    expect(terminalKeyAction(key({ key: 'c', code: 'KeyC', ctrlKey: true }), mac)).toBeNull();
    expect(terminalKeyAction(key({ key: 'v', code: 'KeyV', ctrlKey: true }), mac)).toBeNull();
  });

  it('moves to the start or end of the line on Cmd+Left and Cmd+Right on the Mac', () => {
    const mac = { isMac: true, hasSelection: false };
    expect(terminalKeyAction(key({ key: 'ArrowLeft', metaKey: true }), mac)).toEqual({ type: 'send', data: '\x01' });
    expect(terminalKeyAction(key({ key: 'ArrowRight', metaKey: true }), mac)).toEqual({ type: 'send', data: '\x05' });
    expect(terminalKeyAction(key({ key: 'ArrowLeft', metaKey: true, shiftKey: true }), mac)).toBeNull();
    expect(terminalKeyAction(key({ key: 'ArrowLeft' }), mac)).toBeNull();
  });

  it('leaves other Ctrl keys to the CLI', () => {
    expect(terminalKeyAction(key({ key: 'b', code: 'KeyB', ctrlKey: true }), withSelection)).toBeNull();
    expect(terminalKeyAction(key({ key: 'v', code: 'KeyV', ctrlKey: true, altKey: true }), windows)).toBeNull();
  });
});

describe('isMacPlatform', () => {
  const nav = (platform: string, uaPlatform?: string) =>
    ({
      platform,
      userAgentData: uaPlatform === undefined ? undefined : { platform: uaPlatform },
    }) as unknown as Navigator;

  it('trusts userAgentData over navigator.platform', () => {
    expect(isMacPlatform(nav('Win32', 'macOS'))).toBe(true);
    expect(isMacPlatform(nav('MacIntel', 'Windows'))).toBe(false);
  });

  it('falls back to navigator.platform where userAgentData is missing', () => {
    expect(isMacPlatform(nav('MacIntel'))).toBe(true);
    expect(isMacPlatform(nav('Win32'))).toBe(false);
  });
});
