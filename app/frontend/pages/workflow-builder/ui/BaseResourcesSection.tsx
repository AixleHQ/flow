import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import {
  Accordion,
  AccordionDetails,
  AccordionSummary,
  Autocomplete,
  Box,
  Chip,
  FormControlLabel,
  Switch,
  TextField,
  Typography,
} from '@mui/material';

import type { McpServer } from 'entities/mcp-server';
import type { Asset } from 'features/assets-management';
import type { Skill } from 'features/skills-management';
import type { Tool } from 'features/tools-management';
import type { Workflow } from 'features/workflows';

interface BaseResourcesSectionProps {
  workflow: Workflow;
  tools: Tool[];
  skills: Skill[];
  mcpServers: McpServer[];
  assets: Asset[];
  onConfigChange: (config: Record<string, unknown>) => void;
  readOnly?: boolean;
}

export function BaseResourcesSection({
  workflow,
  tools,
  skills,
  mcpServers,
  assets,
  onConfigChange,
  readOnly = false,
}: BaseResourcesSectionProps) {
  const inheritAll = workflow.inheritAllProjectResources ?? false;
  const disabled = readOnly || inheritAll;

  const selectedTools = tools.filter((t) => (workflow.baseToolIds ?? []).includes(t.id));
  const selectedSkills = skills.filter((s) => (workflow.baseSkillIds ?? []).includes(s.id));
  const selectedMcp = mcpServers.filter((m) => (workflow.baseMcpServerIds ?? []).includes(m.id));
  const selectedAssets = assets.filter((a) => (workflow.baseAssetIds ?? []).includes(a.id));

  return (
    <Accordion defaultExpanded={inheritAll || selectedTools.length > 0 || selectedSkills.length > 0}>
      <AccordionSummary expandIcon={<ExpandMoreIcon />}>
        <Typography sx={{ fontSize: '15px', fontWeight: 600 }}>Base Resources</Typography>
        <Typography sx={{ ml: 1, fontSize: '12px', color: 'text.secondary', alignSelf: 'center' }}>
          Available in all steps
        </Typography>
      </AccordionSummary>
      <AccordionDetails>
        <FormControlLabel
          control={
            <Switch
              checked={inheritAll}
              onChange={(_, checked) => onConfigChange({ inherit_all_project_resources: checked })}
              disabled={readOnly}
              size="small"
            />
          }
          label="Inherit all project resources"
          sx={{ mb: 2 }}
        />

        {inheritAll && (
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            All project tools, skills, and MCP servers are available in every step.
          </Typography>
        )}

        <Box sx={{ opacity: disabled ? 0.5 : 1 }}>
          <Autocomplete
            multiple
            size="small"
            options={tools}
            getOptionLabel={(o) => o.displayName || o.name}
            value={selectedTools}
            onChange={(_, newValue) => onConfigChange({ base_tool_ids: newValue.map((t) => t.id) })}
            renderInput={(params) => <TextField {...params} label="Base Tools" />}
            renderTags={(value, getTagProps) =>
              value.map((option, index) => (
                <Chip
                  {...getTagProps({ index })}
                  key={option.id}
                  label={option.displayName || option.name}
                  size="small"
                />
              ))
            }
            disabled={disabled}
            isOptionEqualToValue={(o, v) => o.id === v.id}
            sx={{ mb: 2 }}
          />

          <Autocomplete
            multiple
            size="small"
            options={skills}
            getOptionLabel={(o) => o.title || o.name}
            value={selectedSkills}
            onChange={(_, newValue) => onConfigChange({ base_skill_ids: newValue.map((s) => s.id) })}
            renderInput={(params) => <TextField {...params} label="Base Skills" />}
            renderTags={(value, getTagProps) =>
              value.map((option, index) => (
                <Chip {...getTagProps({ index })} key={option.id} label={option.title || option.name} size="small" />
              ))
            }
            disabled={disabled}
            isOptionEqualToValue={(o, v) => o.id === v.id}
            sx={{ mb: 2 }}
          />

          <Autocomplete
            multiple
            size="small"
            options={mcpServers}
            getOptionLabel={(o) => o.displayName || o.name}
            value={selectedMcp}
            onChange={(_, newValue) => onConfigChange({ base_mcp_server_ids: newValue.map((m) => m.id) })}
            renderInput={(params) => <TextField {...params} label="Base MCP Servers" />}
            renderTags={(value, getTagProps) =>
              value.map((option, index) => (
                <Chip
                  {...getTagProps({ index })}
                  key={option.id}
                  label={option.displayName || option.name}
                  size="small"
                />
              ))
            }
            disabled={disabled}
            isOptionEqualToValue={(o, v) => o.id === v.id}
            sx={{ mb: 2 }}
          />

          <Autocomplete
            multiple
            size="small"
            options={assets}
            getOptionLabel={(o) => (o.folder ? `${o.folder}/${o.name}` : o.name)}
            value={selectedAssets}
            onChange={(_, newValue) => onConfigChange({ base_asset_ids: newValue.map((a) => a.id) })}
            renderInput={(params) => <TextField {...params} label="Base Assets" />}
            renderTags={(value, getTagProps) =>
              value.map((option, index) => (
                <Chip
                  {...getTagProps({ index })}
                  key={option.id}
                  label={option.folder ? `${option.folder}/${option.name}` : option.name}
                  size="small"
                />
              ))
            }
            disabled={disabled}
            isOptionEqualToValue={(o, v) => o.id === v.id}
          />
        </Box>
      </AccordionDetails>
    </Accordion>
  );
}
