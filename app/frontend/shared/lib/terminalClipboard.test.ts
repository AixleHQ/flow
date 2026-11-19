import type { ClipboardSelectionType } from '@xterm/addon-clipboard';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { terminalClipboardProvider } from './terminalClipboard';

const SYSTEM = 'c' as ClipboardSelectionType;
const PRIMARY = 'p' as ClipboardSelectionType;

describe('terminalClipboardProvider', () => {
  let clipboard: { readText: ReturnType<typeof vi.fn>; writeText: ReturnType<typeof vi.fn> };

  beforeEach(() => {
    clipboard = { readText: vi.fn().mockResolvedValue('the viewer password'), writeText: vi.fn() };
    clipboard.writeText.mockResolvedValue(undefined);
    Object.defineProperty(navigator, 'clipboard', { value: clipboard, configurable: true });
    vi.spyOn(document, 'hasFocus').mockReturnValue(true);
  });

  afterEach(() => {
    vi.restoreAllMocks();
    Reflect.deleteProperty(navigator, 'clipboard');
  });

  it("never reads the viewer's clipboard for the session", async () => {
    const provider = terminalClipboardProvider({ readOnly: false });

    expect(await provider.readText(SYSTEM)).toBe('');
    expect(clipboard.readText).not.toHaveBeenCalled();
  });

  it('copies what the session asks to copy while the page has focus', async () => {
    await terminalClipboardProvider({ readOnly: false }).writeText(SYSTEM, 'https://login.example/device');

    expect(clipboard.writeText).toHaveBeenCalledWith('https://login.example/device');
  });

  it('copies nothing while the page is in the background', async () => {
    vi.mocked(document.hasFocus).mockReturnValue(false);

    await terminalClipboardProvider({ readOnly: false }).writeText(SYSTEM, 'text');

    expect(clipboard.writeText).not.toHaveBeenCalled();
  });

  it('copies nothing from a session the viewer is only watching, or into the primary selection', async () => {
    await terminalClipboardProvider({ readOnly: true }).writeText(SYSTEM, 'text');
    await terminalClipboardProvider({ readOnly: false }).writeText(PRIMARY, 'text');

    expect(clipboard.writeText).not.toHaveBeenCalled();
  });

  it('settles quietly when the browser refuses the write', async () => {
    clipboard.writeText.mockRejectedValue(new DOMException('Document is not focused.', 'NotAllowedError'));

    await expect(terminalClipboardProvider({ readOnly: false }).writeText(SYSTEM, 'text')).resolves.toBeUndefined();
  });
});
