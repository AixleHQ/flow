import { MultiSelect, Switch } from '@mantine/core';

import type { ConfigItemPicker } from '@/types/generated';

interface NamedItem {
  id: number;
  name: string;
}

interface ToolGroup {
  tag: string;
  label: string;
  toolIds: number[];
}

interface Workflow {
  inheritAllProjectResources: boolean;
  baseToolIds: number[];
  baseSkillIds: number[];
  baseMCPServerIds: number[];
  baseAssetIds: number[];
  baseRepositoryIds: number[];
  baseConfigItemIds: number[];
}

interface BaseResourcesTabProps {
  workflow: Workflow;
  tools: NamedItem[];
  toolGroups: ToolGroup[];
  skills: NamedItem[];
  mcpServers: NamedItem[];
  assets: NamedItem[];
  repositories: NamedItem[];
  configItems: ConfigItemPicker[];
  readOnly: boolean;
  onWorkflowChange: (field: string, value: unknown) => void;
}

const GROUP_PREFIX = 'grp:';

export function BaseResourcesTab({
  workflow,
  tools,
  toolGroups,
  skills,
  mcpServers,
  assets,
  repositories,
  configItems,
  readOnly,
  onWorkflowChange,
}: BaseResourcesTabProps) {
  const groupedToolIds = new Set(toolGroups.flatMap((g) => g.toolIds));

  const toolSelectData = [
    ...toolGroups.map((g) => ({ value: `${GROUP_PREFIX}${g.tag}`, label: g.label })),
    ...tools
      .filter((i) => i?.id != null && !groupedToolIds.has(i.id))
      .map((i) => ({ value: String(i.id), label: i.name ?? '' })),
  ];

  const toToolValue = (ids: number[]) => {
    const set = new Set(Array.isArray(ids) ? ids : []);
    const groupTokens = toolGroups
      .filter((g) => g.toolIds.some((id) => set.has(id)))
      .map((g) => `${GROUP_PREFIX}${g.tag}`);
    const individual = [...set].filter((id) => !groupedToolIds.has(id)).map(String);
    return [...groupTokens, ...individual];
  };

  const fromToolValue = (values: string[]): number[] => {
    const ids = new Set<number>();
    (Array.isArray(values) ? values : []).forEach((v) => {
      if (v.startsWith(GROUP_PREFIX)) {
        const group = toolGroups.find((g) => `${GROUP_PREFIX}${g.tag}` === v);
        group?.toolIds.forEach((id) => ids.add(id));
      } else {
        ids.add(Number(v));
      }
    });
    return [...ids];
  };

  const toSelectData = (items: NamedItem[]) =>
    Array.isArray(items)
      ? items.filter((i) => i?.id != null).map((i) => ({ value: String(i.id), label: i.name ?? '' }))
      : [];

  const toStringArr = (ids: number[]) => (Array.isArray(ids) ? ids : []).map(String);
  const toNumberArr = (vals: string[]) => (Array.isArray(vals) ? vals : []).map(Number);

  // A secret is labelled as such in the picker: attaching one is a different
  // decision from attaching a variable, and the label is what makes that visible
  // before the warning below appears.
  const configItemSelectData = (Array.isArray(configItems) ? configItems : [])
    .filter((c) => c?.id != null)
    .map((c) => ({ value: String(c.id), label: c.itemType === 'secret' ? `${c.name} (secret)` : c.name }));

  const baseConfigItemIds = workflow.baseConfigItemIds ?? [];

  return (
    <div style={{ overflowY: 'auto', flex: 1, background: 'var(--bg)' }}>
      <div style={{ padding: '28px 24px', maxWidth: 640 }}>
        {/* Heading */}
        <div
          style={{
            fontSize: 16,
            fontWeight: 700,
            color: 'var(--text-1)',
            letterSpacing: '-0.02em',
            marginBottom: 4,
          }}
        >
          Base Resources
        </div>
        <div style={{ fontSize: 13, color: 'var(--text-2)', marginBottom: 20 }}>
          Default resources available to every session. Sessions can add their own on top.
        </div>

        {/* Inherit toggle card — toggle on LEFT, text on right */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 12,
            padding: '10px 14px',
            background: 'var(--bg-card)',
            borderRadius: 7,
            border: '1px solid var(--border)',
            marginBottom: 20,
          }}
        >
          <Switch
            checked={workflow.inheritAllProjectResources}
            onChange={(e) => onWorkflowChange('inheritAllProjectResources', e.currentTarget.checked)}
            disabled={readOnly}
            style={{ flexShrink: 0 }}
          />
          <div>
            <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)' }}>Inherit all project resources</div>
            <div style={{ fontSize: 11, color: 'var(--text-3)', marginTop: 2 }}>
              Tools, skills, MCP servers, and assets from the project level are included automatically. Project
              repositories are used only while nothing below selects one.
            </div>
          </div>
        </div>

        {/* 2-column grid */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
          {(
            [
              {
                label: 'Tools',
                placeholder: 'Select tools…',
                data: toolSelectData,
                value: toToolValue(workflow.baseToolIds),
                onChange: (v: string[]) => onWorkflowChange('baseToolIds', fromToolValue(v)),
                isEmpty: workflow.baseToolIds.length === 0,
                supersededByInherit: true,
                emptyHint: 'None added',
              },
              {
                label: 'Skills',
                placeholder: 'Select skills…',
                data: toSelectData(skills),
                value: toStringArr(workflow.baseSkillIds),
                onChange: (v: string[]) => onWorkflowChange('baseSkillIds', toNumberArr(v)),
                isEmpty: workflow.baseSkillIds.length === 0,
                supersededByInherit: true,
                emptyHint: 'None added',
              },
              {
                label: 'MCP Servers',
                placeholder: 'Select MCP servers…',
                data: toSelectData(mcpServers),
                value: toStringArr(workflow.baseMCPServerIds),
                onChange: (v: string[]) => onWorkflowChange('baseMCPServerIds', toNumberArr(v)),
                isEmpty: workflow.baseMCPServerIds.length === 0,
                supersededByInherit: true,
                emptyHint: 'None added',
              },
              {
                label: 'Assets',
                placeholder: 'Select assets…',
                data: toSelectData(assets),
                value: toStringArr(workflow.baseAssetIds),
                onChange: (v: string[]) => onWorkflowChange('baseAssetIds', toNumberArr(v)),
                isEmpty: workflow.baseAssetIds.length === 0,
                supersededByInherit: true,
                emptyHint: 'None added',
              },
              {
                label: 'Secrets & Variables',
                placeholder: 'Select secrets and variables…',
                data: configItemSelectData,
                value: toStringArr(baseConfigItemIds),
                onChange: (v: string[]) => onWorkflowChange('baseConfigItemIds', toNumberArr(v)),
                isEmpty: baseConfigItemIds.length === 0,
                supersededByInherit: true,
                emptyHint: 'None added — steps can attach their own',
              },
              {
                // Repositories stay selectable while "inherit all" is on: unlike the
                // resources above, they are not added on top of the project-wide set —
                // choosing one replaces it. Disabling this would remove the only way to
                // narrow a workflow down to a single repository.
                label: 'Repositories',
                placeholder: 'Select repositories…',
                data: toSelectData(repositories),
                value: toStringArr(workflow.baseRepositoryIds),
                onChange: (v: string[]) => onWorkflowChange('baseRepositoryIds', toNumberArr(v)),
                isEmpty: workflow.baseRepositoryIds.length === 0,
                supersededByInherit: false,
                emptyHint: workflow.inheritAllProjectResources
                  ? 'All project repositories — select to narrow'
                  : 'None added — steps get code only from their own selection',
              },
            ] as const
          ).map(({ label, placeholder, data, value, onChange, isEmpty, supersededByInherit, emptyHint }) => (
            <div key={label}>
              <div
                style={{
                  fontSize: 13,
                  fontWeight: 500,
                  color: 'var(--text-1)',
                  marginBottom: 5,
                }}
              >
                {label}
              </div>
              <MultiSelect
                data={data}
                value={[...value]}
                onChange={onChange}
                disabled={readOnly || (supersededByInherit && workflow.inheritAllProjectResources)}
                searchable
                placeholder={placeholder}
                styles={{
                  input: {
                    background: 'var(--bg-card)',
                    border: '1px solid var(--border)',
                    borderRadius: 5,
                    fontSize: 13,
                    minHeight: 36,
                  },
                }}
              />
              {isEmpty && <div style={{ fontSize: 11, color: 'var(--text-3)', marginTop: 6 }}>{emptyHint}</div>}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
