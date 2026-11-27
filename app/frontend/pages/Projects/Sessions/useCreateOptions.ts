import { router, usePage } from '@inertiajs/react';
import { useEffect } from 'react';

import type { IntegrationPicker, RunnerSummary } from '@/types/generated';

import type { AssetPickerItem } from 'shared/components/AssetPicker';
import { ConfigItemOption } from 'shared/components/SessionNewForm';
import type { ToolGroup } from 'shared/lib/toolPicker';

interface NamedItem {
  id: number;
  name: string;
}

interface WorkflowOption {
  id: number;
  name: string;
  runnerId?: number | null;
  integrationIds?: number[];
  steps: {
    id: number;
    name: string;
    position: number;
    allowNonInteractive: boolean;
    dependsOnStepIds: number[];
  }[];
}

export interface CreateOptions {
  agents: NamedItem[];
  tools: NamedItem[];
  toolGroups: ToolGroup[];
  skills: NamedItem[];
  mcpServers: NamedItem[];
  assets: AssetPickerItem[];
  repositories: NamedItem[];
  agentModels: {
    agentType: string;
    models: { modelId: string; displayName: string; reasoningEffortLevels: string[] }[];
    defaultModel?: string | null;
  }[];
  configuredAgents: string[];
  defaultAgentRuntime: string | null;
  workflows: WorkflowOption[];
  configItems: ConfigItemOption[];
  /** Coder, Slack, Teams and Azure DevOps integrations a session can be given. */
  integrations?: IntegrationPicker[];
  /** What the form preselects: the project's Coder, its chat installs and Azure DevOps connections. */
  defaultIntegrationIds?: number[];
  /** Absent from a server that predates runners. */
  runners?: RunnerSummary[];
  costHint?: { avgCostCentsByRuntime: Record<string, number>; monthToDateCents: number };
}

/**
 * The option lists both create drawers need. They are an `optional` Inertia
 * prop, so the list page — which most visits never create anything from —
 * doesn't pay to serialize every tool, skill, asset and workflow in the project
 * on the way in. The first drawer open fetches them; later opens reuse them.
 */
export function useCreateOptions(opened: boolean): CreateOptions | null {
  const { createOptions } = usePage().props as unknown as { createOptions?: CreateOptions };

  useEffect(() => {
    if (!opened || createOptions) return;
    router.reload({ only: ['create_options'] });
  }, [opened, createOptions]);

  return createOptions ?? null;
}
