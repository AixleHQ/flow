import { useCallback, useEffect, useRef, useState } from 'react';

import type { Step, Workflow } from '@/types/generated';

import { apiRequest } from 'shared/lib/apiFetch';
import { checkApiV1ProjectWorkflowAggregatePath } from 'shared/routes';

import { aggregatePayload } from './builderDraft';
import type { WorkflowIssue } from './dataFlow';

const CHECK_DELAY_MS = 600;

/**
 * The part of the draft the data-flow check reads. Edits outside it (a name, an agent, a retry
 * policy) cannot change what the check says, so they do not send a request.
 */
export function dataFlowKey(workflow: Workflow, sortedSteps: Step[]): string {
  const { config, steps } = aggregatePayload(workflow, sortedSteps);
  return JSON.stringify({
    base: [config.base_asset_ids, config.base_mcp_server_ids, config.inherit_all_project_resources],
    steps: steps.map((s) => [
      s.key,
      s.instructions,
      s.dependsOnStepIds,
      s.assetIds,
      s.mcpServerIds,
      s.inputAssetSpecs,
      s.outputAssetSpecs,
    ]),
  });
}

interface Options {
  projectId: number | null;
  workflow: Workflow;
  sortedSteps: Step[];
  /** Issues of the saved workflow, sent with the page; absent from an older server. */
  initialIssues: WorkflowIssue[] | undefined;
}

/**
 * Keeps the builder's data-flow issues in step with the draft: the server checks the unsaved
 * payload a moment after the last relevant edit. A failed check keeps the last answer.
 */
export function useWorkflowIssues({ projectId, workflow, sortedSteps, initialIssues }: Options) {
  const [issues, setIssues] = useState<WorkflowIssue[]>(initialIssues ?? []);
  const key = dataFlowKey(workflow, sortedSteps);
  // The draft the current issues describe; nothing is sent while the draft still matches it.
  const checkedKey = useRef<string | null>(initialIssues ? key : null);
  const sequence = useRef(0);
  const latest = useRef({ workflow, sortedSteps, key });

  useEffect(() => {
    latest.current = { workflow, sortedSteps, key };
  });

  const check = useCallback(async () => {
    if (projectId == null) return;
    const { workflow: wf, sortedSteps: steps, key: sentKey } = latest.current;
    const ticket = ++sequence.current;
    try {
      const result = await apiRequest<{ issues?: WorkflowIssue[] }>(
        checkApiV1ProjectWorkflowAggregatePath(projectId, wf.id),
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ aggregate: aggregatePayload(wf, steps) }),
        },
      );
      if (ticket !== sequence.current) return;
      checkedKey.current = sentKey;
      setIssues(result.issues ?? []);
    } catch {
      // A check is advice; Save and Run still answer for themselves.
    }
  }, [projectId]);

  useEffect(() => {
    if (projectId == null || key === checkedKey.current) return;
    const timer = window.setTimeout(() => void check(), checkedKey.current === null ? 0 : CHECK_DELAY_MS);
    return () => window.clearTimeout(timer);
  }, [key, projectId, check]);

  /** Issues the Save answered with, for the state it saved. */
  const replaceIssues = useCallback((next: WorkflowIssue[], savedKey: string) => {
    sequence.current += 1;
    checkedKey.current = savedKey;
    setIssues(next);
  }, []);

  return { issues, replaceIssues };
}
