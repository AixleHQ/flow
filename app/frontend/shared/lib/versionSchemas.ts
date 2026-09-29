import type { FieldSpec } from './versionDiff';

// What a diff shows for each versioned type, in display order. Keys are the
// snapshot's own (app/services/versions/snapshots/*.rb); a snapshot field left
// out here is still stored and reverted, just not listed in the diff.

export type VersionableType = 'Workflow' | 'Agent' | 'Skill' | 'Tool' | 'MCPServer';

const AGENT: FieldSpec[] = [
  { kind: 'scalar', key: 'title', label: 'Title' },
  { kind: 'scalar', key: 'name', label: 'Name' },
  { kind: 'scalar', key: 'icon', label: 'Icon' },
  { kind: 'text', key: 'persona', label: 'Persona' },
  { kind: 'text', key: 'communication_style', label: 'Communication style' },
  { kind: 'text', key: 'principles', label: 'Principles' },
];

const SKILL: FieldSpec[] = [
  { kind: 'scalar', key: 'title', label: 'Title' },
  { kind: 'scalar', key: 'name', label: 'Name' },
  { kind: 'text', key: 'description', label: 'Description' },
  { kind: 'text', key: 'content', label: 'SKILL.md' },
  { kind: 'textMap', key: 'files', label: 'Files' },
  { kind: 'scalar', key: 'package', label: 'Package' },
  { kind: 'scalar', key: 'content_hash', label: 'Registry digest' },
];

const TOOL: FieldSpec[] = [
  { kind: 'scalar', key: 'display_name', label: 'Name' },
  { kind: 'scalar', key: 'name', label: 'Identifier' },
  { kind: 'text', key: 'description', label: 'Description' },
  { kind: 'scalar', key: 'docker_image', label: 'Docker image' },
  { kind: 'text', key: 'command', label: 'Command' },
  { kind: 'scalar', key: 'execution_mode', label: 'Execution mode' },
  { kind: 'json', key: 'input_schema', label: 'Input schema' },
  { kind: 'list', key: 'required_config_items', label: 'Required config items' },
  { kind: 'scalar', key: 'requires_integration', label: 'Requires integration' },
  { kind: 'list', key: 'tags', label: 'Tags' },
  { kind: 'scalar', key: 'enabled', label: 'Enabled' },
  {
    kind: 'collection',
    key: 'files',
    label: 'Files',
    itemKey: 'path',
    itemLabel: 'path',
    fields: [
      { kind: 'text', key: 'content', label: 'Content' },
      { kind: 'json', key: 'file_data', label: 'Uploaded file' },
    ],
  },
];

const MCP_SERVER: FieldSpec[] = [
  { kind: 'scalar', key: 'name', label: 'Name' },
  { kind: 'text', key: 'description', label: 'Description' },
  { kind: 'scalar', key: 'transport', label: 'Transport' },
  { kind: 'scalar', key: 'url', label: 'URL' },
  { kind: 'scalar', key: 'command', label: 'Command' },
  { kind: 'list', key: 'args', label: 'Arguments' },
  { kind: 'scalar', key: 'auth_type', label: 'Authentication' },
  { kind: 'scalar', key: 'credential_scope', label: 'Credentials' },
  { kind: 'scalar', key: 'enabled', label: 'Enabled' },
  { kind: 'scalar', key: 'connector_version', label: 'Connector version' },
  { kind: 'secretMap', key: 'secrets.headers', label: 'Headers' },
  { kind: 'secretMap', key: 'secrets.env', label: 'Environment variables' },
];

const SUB_STEP: FieldSpec[] = [
  { kind: 'scalar', key: 'name', label: 'Name' },
  { kind: 'text', key: 'instructions', label: 'Instructions' },
  { kind: 'scalar', key: 'required', label: 'Required' },
];

const STEP: FieldSpec[] = [
  { kind: 'scalar', key: 'name', label: 'Name' },
  { kind: 'text', key: 'instructions', label: 'Instructions' },
  { kind: 'ref', key: 'agent_id', label: 'Agent', model: 'Agent' },
  { kind: 'stepRefs', key: 'depends_on_step_ids', label: 'Depends on' },
  { kind: 'scalar', key: 'preferred_model', label: 'Model' },
  { kind: 'scalar', key: 'required_agent_runtime', label: 'Agent runtime' },
  { kind: 'refs', key: 'tool_ids', label: 'Tools', model: 'Tool' },
  { kind: 'refs', key: 'skill_ids', label: 'Skills', model: 'Skill' },
  { kind: 'refs', key: 'mcp_server_ids', label: 'MCP servers', model: 'MCPServer' },
  { kind: 'refs', key: 'repository_ids', label: 'Repositories', model: 'Repository' },
  { kind: 'refs', key: 'config_item_ids', label: 'Config items', model: 'ConfigItem' },
  { kind: 'refs', key: 'asset_ids', label: 'Assets', model: 'Asset' },
  { kind: 'json', key: 'input_asset_specs', label: 'Input assets' },
  { kind: 'json', key: 'output_asset_specs', label: 'Output assets' },
  { kind: 'scalar', key: 'skip_policy', label: 'Skip policy' },
  { kind: 'scalar', key: 'on_failure', label: 'On failure' },
  { kind: 'scalar', key: 'max_retries', label: 'Max retries' },
  { kind: 'scalar', key: 'allow_non_interactive', label: 'Allow non-interactive' },
  { kind: 'scalar', key: 'bmad_enabled', label: 'BMAD' },
  { kind: 'collection', key: 'sub_steps', label: 'Sub-steps', itemKey: 'id', itemLabel: 'name', fields: SUB_STEP },
];

const WORKFLOW: FieldSpec[] = [
  { kind: 'scalar', key: 'name', label: 'Name' },
  { kind: 'text', key: 'description', label: 'Description' },
  { kind: 'scalar', key: 'config.inherit_all_project_resources', label: 'Inherit all project resources' },
  { kind: 'refs', key: 'config.base_tool_ids', label: 'Workflow tools', model: 'Tool' },
  { kind: 'refs', key: 'config.base_skill_ids', label: 'Workflow skills', model: 'Skill' },
  { kind: 'refs', key: 'config.base_mcp_server_ids', label: 'Workflow MCP servers', model: 'MCPServer' },
  { kind: 'refs', key: 'config.base_repository_ids', label: 'Workflow repositories', model: 'Repository' },
  { kind: 'refs', key: 'config.base_config_item_ids', label: 'Workflow config items', model: 'ConfigItem' },
  { kind: 'refs', key: 'config.base_asset_ids', label: 'Workflow assets', model: 'Asset' },
  { kind: 'collection', key: 'steps', label: 'Steps', itemKey: 'id', itemLabel: 'name', fields: STEP },
];

export const VERSION_SCHEMAS: Record<VersionableType, FieldSpec[]> = {
  Workflow: WORKFLOW,
  Agent: AGENT,
  Skill: SKILL,
  Tool: TOOL,
  MCPServer: MCP_SERVER,
};
