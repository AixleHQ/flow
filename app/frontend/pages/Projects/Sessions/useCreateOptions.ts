import { router, usePage } from '@inertiajs/react';
import { useEffect } from 'react';

import { ConfigItemOption } from 'shared/components/SessionNewForm';

export interface NamedItem {
  id: number;
  name: string;
}

export interface WorkflowOption {
  id: number;
  name: string;
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
  skills: NamedItem[];
  mcpServers: NamedItem[];
  assets: NamedItem[];
  repositories: NamedItem[];
  agentModels: { agentType: string; models: { modelId: string; displayName: string }[] }[];
  configuredAgents: string[];
  defaultAgentRuntime: string | null;
  workflows: WorkflowOption[];
  configItems: ConfigItemOption[];
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
