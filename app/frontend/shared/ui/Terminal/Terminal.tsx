import { FitAddon } from '@xterm/addon-fit';
import { WebLinksAddon } from '@xterm/addon-web-links';
import { Terminal as XTerm } from '@xterm/xterm';
import { useEffect, useRef, useImperativeHandle, forwardRef } from 'react';
import '@xterm/xterm/css/xterm.css';

export interface TerminalHandle {
  write: (data: string) => void;
  writeln: (data: string) => void;
  clear: () => void;
  reset: () => void;
  focus: () => void;
}

interface TerminalProps {
  onData?: (data: string) => void;
  onResize?: (cols: number, rows: number) => void;
  fontSize?: number;
  className?: string;
}

export const Terminal = forwardRef<TerminalHandle, TerminalProps>(
  ({ onData, onResize, fontSize = 14, className }, ref) => {
    const containerRef = useRef<HTMLDivElement>(null);
    const terminalRef = useRef<XTerm | null>(null);
    const fitAddonRef = useRef<FitAddon | null>(null);

    // Expose methods via ref
    useImperativeHandle(ref, () => ({
      write: (data: string) => {
        terminalRef.current?.write(data);
      },
      writeln: (data: string) => {
        terminalRef.current?.writeln(data);
      },
      clear: () => {
        terminalRef.current?.clear();
      },
      reset: () => {
        // Clear screen and move cursor to top-left
        terminalRef.current?.write('\x1b[2J\x1b[H');
      },
      focus: () => {
        terminalRef.current?.focus();
      },
    }));

    // Initialize terminal
    useEffect(() => {
      if (!containerRef.current) return;

      const terminal = new XTerm({
        fontSize,
        fontFamily: 'Menlo, Monaco, "Courier New", monospace',
        theme: {
          background: '#1e1e1e',
          foreground: '#d4d4d4',
          cursor: '#d4d4d4',
          cursorAccent: '#1e1e1e',
          selectionBackground: '#264f78',
          black: '#1e1e1e',
          red: '#f44747',
          green: '#6a9955',
          yellow: '#dcdcaa',
          blue: '#569cd6',
          magenta: '#c586c0',
          cyan: '#4ec9b0',
          white: '#d4d4d4',
          brightBlack: '#808080',
          brightRed: '#f44747',
          brightGreen: '#6a9955',
          brightYellow: '#dcdcaa',
          brightBlue: '#569cd6',
          brightMagenta: '#c586c0',
          brightCyan: '#4ec9b0',
          brightWhite: '#ffffff',
        },
        cursorBlink: true,
        cursorStyle: 'block',
        scrollback: 10000,
        convertEol: true,
      });

      const fitAddon = new FitAddon();
      const webLinksAddon = new WebLinksAddon();

      terminal.loadAddon(fitAddon);
      terminal.loadAddon(webLinksAddon);

      terminal.open(containerRef.current);

      // Initial fit
      requestAnimationFrame(() => {
        fitAddon.fit();
      });

      terminalRef.current = terminal;
      fitAddonRef.current = fitAddon;

      // Handle user input
      const dataDisposable = terminal.onData((data) => {
        onData?.(data);
      });

      // Handle resize
      const resizeObserver = new ResizeObserver(() => {
        requestAnimationFrame(() => {
          fitAddon.fit();
          onResize?.(terminal.cols, terminal.rows);
        });
      });
      resizeObserver.observe(containerRef.current);

      return () => {
        dataDisposable.dispose();
        resizeObserver.disconnect();
        terminal.dispose();
        terminalRef.current = null;
        fitAddonRef.current = null;
      };
    }, [fontSize, onData, onResize]);

    return (
      <div
        ref={containerRef}
        className={className}
        style={{
          width: '100%',
          height: '100%',
          backgroundColor: '#1e1e1e',
        }}
      />
    );
  },
);

Terminal.displayName = 'Terminal';
