import { Box, MultiSelect, Stack, Switch, Text } from '@mantine/core';

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
}

interface BaseResourcesTabProps {
  workflow: Workflow;
  tools: NamedItem[];
  toolGroups: ToolGroup[];
  skills: NamedItem[];
  mcpServers: NamedItem[];
  assets: NamedItem[];
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

  return (
    <Box p={24}>
      <Text fw={600} size="md" style={{ color: 'var(--text-1)' }} mb={4}>
        Base Resources
      </Text>
      <Text size="sm" style={{ color: 'var(--text-2)' }} mb={20}>
        Default resources available to every session. Sessions can add their own on top.
      </Text>

      {/* Inherit toggle card */}
      <Box
        mb={20}
        p={16}
        style={{
          background: 'var(--bg-card)',
          border: '1px solid var(--border)',
          borderRadius: 8,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 16,
        }}
      >
        <Box>
          <Text size="sm" fw={700} style={{ color: 'var(--text-1)' }}>
            Inherit all project resources
          </Text>
          <Text size="xs" style={{ color: 'var(--text-2)' }} mt={2}>
            Tools, skills, MCP servers, and assets from the project level are included automatically.
          </Text>
        </Box>
        <Switch
          checked={workflow.inheritAllProjectResources}
          onChange={(e) => onWorkflowChange('inheritAllProjectResources', e.currentTarget.checked)}
          disabled={readOnly}
        />
      </Box>

      {/* 2-column grid */}
      <Box
        style={{
          display: 'grid',
          gridTemplateColumns: '1fr 1fr',
          gap: 16,
        }}
      >
        <Stack gap="xs">
          <Text
            size="xs"
            fw={600}
            style={{ color: 'var(--text-2)', textTransform: 'uppercase', letterSpacing: '0.08em' }}
          >
            Tools
          </Text>
          <MultiSelect
            data={toolSelectData}
            value={toToolValue(workflow.baseToolIds)}
            onChange={(v) => onWorkflowChange('baseToolIds', fromToolValue(v))}
            disabled={readOnly || workflow.inheritAllProjectResources}
            searchable
            placeholder={workflow.baseToolIds.length === 0 ? 'None added' : undefined}
          />
        </Stack>

        <Stack gap="xs">
          <Text
            size="xs"
            fw={600}
            style={{ color: 'var(--text-2)', textTransform: 'uppercase', letterSpacing: '0.08em' }}
          >
            Skills
          </Text>
          <MultiSelect
            data={toSelectData(skills)}
            value={toStringArr(workflow.baseSkillIds)}
            onChange={(v) => onWorkflowChange('baseSkillIds', toNumberArr(v))}
            disabled={readOnly || workflow.inheritAllProjectResources}
            searchable
            placeholder={workflow.baseSkillIds.length === 0 ? 'None added' : undefined}
          />
        </Stack>

        <Stack gap="xs">
          <Text
            size="xs"
            fw={600}
            style={{ color: 'var(--text-2)', textTransform: 'uppercase', letterSpacing: '0.08em' }}
          >
            MCP Servers
          </Text>
          <MultiSelect
            data={toSelectData(mcpServers)}
            value={toStringArr(workflow.baseMCPServerIds)}
            onChange={(v) => onWorkflowChange('baseMCPServerIds', toNumberArr(v))}
            disabled={readOnly || workflow.inheritAllProjectResources}
            searchable
            placeholder={workflow.baseMCPServerIds.length === 0 ? 'None added' : undefined}
          />
        </Stack>

        <Stack gap="xs">
          <Text
            size="xs"
            fw={600}
            style={{ color: 'var(--text-2)', textTransform: 'uppercase', letterSpacing: '0.08em' }}
          >
            Assets
          </Text>
          <MultiSelect
            data={toSelectData(assets)}
            value={toStringArr(workflow.baseAssetIds)}
            onChange={(v) => onWorkflowChange('baseAssetIds', toNumberArr(v))}
            disabled={readOnly || workflow.inheritAllProjectResources}
            searchable
            placeholder={workflow.baseAssetIds.length === 0 ? 'None added' : undefined}
          />
        </Stack>
      </Box>
    </Box>
  );
}
