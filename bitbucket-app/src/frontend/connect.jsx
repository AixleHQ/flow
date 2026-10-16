import React, { useCallback, useEffect, useState } from "react";
import ForgeReconciler, { Button, Heading, SectionMessage, Spinner, Text } from "@forge/react";
import { invokeRemote, router } from "@forge/bridge";

// Workspace settings → Aixle Flow. Every call goes to the Aixle deployment
// through Forge, which signs it with the invocation token and the app token;
// Aixle checks that the person viewing this page administers the workspace.
// Aixle answers refusals with 200 and `ok: false`, because the bridge rejects a
// non-2xx response before the page could read why.
const UI_PATH = "/webhooks/bitbucket/forge/ui";

async function call(action) {
  const response = await invokeRemote({ path: `${UI_PATH}/${action}`, method: "POST", body: {} });
  return response.body || { ok: false, message: "Aixle did not answer." };
}

function Connect() {
  const [status, setStatus] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const run = useCallback(async (action, onAnswer) => {
    setBusy(true);
    setError(null);
    try {
      const body = await call(action);
      if (body.ok === false) setError(body.message || "Aixle refused the request.");
      else await onAnswer(body);
    } catch {
      setError("Aixle could not be reached. Try again in a minute.");
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void run("status", (body) => setStatus(body));
  }, [run]);

  const connect = () => run("connect", (body) => router.open(body.url));
  const disconnect = () => run("disconnect", (body) => setStatus(body));

  if (!status && !error) return <Spinner label="Asking Aixle" />;

  return (
    <>
      <Heading as="h1">Aixle Flow</Heading>
      {error && (
        <SectionMessage appearance="error" title="Not done">
          <Text>{error}</Text>
        </SectionMessage>
      )}
      {status?.bound ? (
        <>
          <SectionMessage appearance="confirmation" title={`Connected to ${status.company}`}>
            <Text>
              {status.projects.length > 0
                ? `Projects: ${status.projects.join(", ")}.`
                : "No project uses this workspace yet."}
            </Text>
            {status.bound_by && <Text>{`Connected by ${status.bound_by}.`}</Text>}
          </SectionMessage>
          <Text>
            Connect again to add another project of the same company. Disconnect stops every Aixle project from using
            this workspace; the app stays installed.
          </Text>
          <Button onClick={connect} isDisabled={busy}>
            Connect another project
          </Button>
          <Button appearance="danger" onClick={disconnect} isDisabled={busy}>
            Disconnect
          </Button>
        </>
      ) : (
        status && (
          <>
            <Text>
              Connect this workspace to an Aixle project. Aixle opens in a new tab, where you sign in and choose the
              project. The link works once, for 10 minutes; open it yourself rather than sending it to someone.
            </Text>
            <Button appearance="primary" onClick={connect} isDisabled={busy}>
              Connect
            </Button>
          </>
        )
      )}
    </>
  );
}

ForgeReconciler.render(
  <React.StrictMode>
    <Connect />
  </React.StrictMode>,
);
