import { router } from '@inertiajs/react';
import { Button, Group, Stack, Text, Title } from '@mantine/core';
import { useEffect } from 'react';

interface AppCrashFallbackProps {
  resetError: () => void;
}

/**
 * What the app shows when a page throws while rendering, instead of a blank
 * screen. The error has already gone to Sentry by the time this renders. Any
 * Inertia visit — Back included — clears it and renders the page it lands on.
 */
export function AppCrashFallback({ resetError }: AppCrashFallbackProps) {
  useEffect(() => router.on('navigate', resetError), [resetError]);

  return (
    <Stack role="alert" align="center" justify="center" mih="100vh" p="xl" gap="md">
      <Title order={2}>This page could not be shown</Title>
      <Text c="dimmed" ta="center" maw={480}>
        Something went wrong while drawing it, and the error has been reported. Reloading usually fixes it; if it does
        not, go back to where you were.
      </Text>
      <Group>
        <Button onClick={() => window.location.reload()}>Reload the page</Button>
        <Button variant="default" onClick={() => window.history.back()}>
          Go back
        </Button>
      </Group>
    </Stack>
  );
}

/**
 * The last resort, for a failure in the providers themselves: nothing from the
 * theme is available here, so it uses the browser's own colors.
 */
export function ProviderCrashFallback() {
  return (
    <div
      role="alert"
      style={{
        minHeight: '100vh',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 12,
        fontFamily: 'system-ui, sans-serif',
        background: 'Canvas',
        color: 'CanvasText',
      }}
    >
      <h1 style={{ fontSize: 22, margin: 0 }}>The app could not start</h1>
      <p style={{ margin: 0 }}>The error has been reported.</p>
      <button type="button" onClick={() => window.location.reload()}>
        Reload the page
      </button>
    </div>
  );
}
