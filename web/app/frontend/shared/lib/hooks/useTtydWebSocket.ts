import { useCallback, useEffect, useRef, useState } from 'react';

interface UseTtydWebSocketOptions {
  wsUrl: string | null;
  onOutput?: (data: string) => void;
  onError?: (message: string) => void;
  onConnect?: () => void;
  onDisconnect?: (reason: string) => void;
}

interface UseTtydWebSocketReturn {
  connected: boolean;
  connecting: boolean;
  sendInput: (data: string) => void;
  sendResize: (cols: number, rows: number) => void;
}

/**
 * Hook for connecting to ttyd WebSocket terminal
 * ttyd protocol: https://github.com/tsl0922/ttyd
 *
 * Message types:
 * - Client to Server:
 *   - '0' + data: input data
 *   - '1' + JSON: resize {columns, rows}
 *   - '2': client ping
 *
 * - Server to Client:
 *   - '0' + data: output data
 *   - '1' + JSON: window title
 *   - '2': server ping
 */
export const useTtydWebSocket = ({
  wsUrl,
  onOutput,
  onError,
  onConnect,
  onDisconnect,
}: UseTtydWebSocketOptions): UseTtydWebSocketReturn => {
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<number | null>(null);

  const cleanup = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      window.clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }
  }, []);

  const connect = useCallback(() => {
    if (!wsUrl) return;

    cleanup();
    setConnecting(true);

    const ws = new WebSocket(wsUrl);
    wsRef.current = ws;

    ws.binaryType = 'arraybuffer';

    ws.onopen = () => {
      setConnecting(false);
      setConnected(true);
      onConnect?.();
    };

    ws.onmessage = (event) => {
      if (event.data instanceof ArrayBuffer) {
        const data = new Uint8Array(event.data);
        if (data.length > 0) {
          const messageType = String.fromCharCode(data[0]);
          const payload = new TextDecoder().decode(data.slice(1));

          switch (messageType) {
            case '0': // Output data
              onOutput?.(payload);
              break;
            case '1': // Window title (ignore for now)
              break;
            case '2': // Server ping - respond with pong
              ws.send(new TextEncoder().encode('2'));
              break;
            default:
              console.log('[ttyd] Unknown message type:', messageType);
          }
        }
      } else if (typeof event.data === 'string') {
        // Handle text messages (some ttyd versions use text)
        if (event.data.length > 0) {
          const messageType = event.data[0];
          const payload = event.data.slice(1);

          switch (messageType) {
            case '0':
              onOutput?.(payload);
              break;
            case '1':
              break;
            case '2':
              ws.send('2');
              break;
            default:
              console.log('[ttyd] Unknown text message type:', messageType);
          }
        }
      }
    };

    ws.onerror = (error) => {
      console.error('[ttyd] WebSocket error:', error);
      onError?.('WebSocket connection error');
    };

    ws.onclose = (event) => {
      setConnected(false);
      setConnecting(false);
      onDisconnect?.(event.reason || 'Connection closed');

      // Auto-reconnect after 2 seconds if not intentionally closed
      if (wsUrl && event.code !== 1000) {
        reconnectTimeoutRef.current = window.setTimeout(() => {
          connect();
        }, 2000);
      }
    };
  }, [wsUrl, onOutput, onError, onConnect, onDisconnect, cleanup]);

  useEffect(() => {
    connect();
    return cleanup;
  }, [connect, cleanup]);

  const sendInput = useCallback((data: string) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      // ttyd protocol: '0' + input data
      const message = '0' + data;
      wsRef.current.send(new TextEncoder().encode(message));
    }
  }, []);

  const sendResize = useCallback((cols: number, rows: number) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      // ttyd protocol: '1' + JSON with columns and rows
      const message = '1' + JSON.stringify({ columns: cols, rows: rows });
      wsRef.current.send(new TextEncoder().encode(message));
    }
  }, []);

  return {
    connected,
    connecting,
    sendInput,
    sendResize,
  };
};
