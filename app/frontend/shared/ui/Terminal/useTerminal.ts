import { useRef, useCallback } from 'react';

import type { TerminalHandle } from './Terminal';

export function useTerminal() {
  const terminalRef = useRef<TerminalHandle>(null);

  const write = useCallback((data: string) => {
    terminalRef.current?.write(data);
  }, []);

  const writeln = useCallback((data: string) => {
    terminalRef.current?.writeln(data);
  }, []);

  const clear = useCallback(() => {
    terminalRef.current?.clear();
  }, []);

  const focus = useCallback(() => {
    terminalRef.current?.focus();
  }, []);

  return {
    terminalRef,
    write,
    writeln,
    clear,
    focus,
  };
}
