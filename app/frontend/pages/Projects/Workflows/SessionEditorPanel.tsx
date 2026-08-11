import { MultiSelect, Select, Switch } from '@mantine/core';
import {
  IconArrowsExchange2,
  IconArrowUpRight,
  IconCpu,
  IconFileDescription,
  IconInfoCircle,
  IconLayersIntersect,
  IconListTree,
  IconMaximize,
  IconMinimize,
  IconShield,
} from '@tabler/icons-react';
import { useState } from 'react';

import classes from './BuilderPage.module.css';

interface NamedItem {
  id: number;
  name: string;
}

interface ToolGroup {
  tag: string;
  label: string;
  toolIds: number[];
}

interface AssetSpec {
  name: string;
  assetType: string;
  required: boolean;
  namePattern?: string | null;
}

interface Step {
  id: number;
  name: string;
  instructions: string | null;
  position: number;
  agentId: number | null;
  requiredAgentRuntime: string | null;
  preferredModel: string | null;
  allowNonInteractive: boolean;
  skipPolicy: string;
  onFailure: string;
  bmadEnabled: boolean;
  dependsOnStepIds: number[];
  toolIds: number[];
  mcpServerIds: number[];
  skillIds: number[];
  assetIds: number[];
  repositoryIds: number[];
  inputAssetSpecs: AssetSpec[];
  outputAssetSpecs: AssetSpec[];
}

const SKIP_POLICY_TEXTS: Record<string, string> = {
  never: 'This session always runs when the workflow is triggered.',
  if_outputs_exist: 'Skips this session if its output artifacts already exist.',
  manual: 'You decide at run time whether to run this session.',
};

const ON_FAILURE_TEXTS: Record<string, string> = {
  fail: 'The entire workflow run stops immediately if this session fails.',
  retry: 'The session is retried automatically before failing.',
  skip: 'The workflow continues even if this session fails.',
};

interface SectionLabelProps {
  icon: React.ReactNode;
  label: string;
}

function SectionLabel({ icon, label }: SectionLabelProps) {
  return (
    <div className={classes.secLabel}>
      <span className={classes.secLabelIcon}>{icon}</span>
      {label}
    </div>
  );
}

interface AssetRowsProps {
  specs: AssetSpec[];
  onChange: (specs: AssetSpec[]) => void;
  showNamePattern: boolean;
  disabled: boolean;
  kind: 'input' | 'output';
}

function AssetRows({ specs, onChange, showNamePattern, disabled, kind }: AssetRowsProps) {
  const addSpec = () => onChange([...specs, { name: '', assetType: 'file', required: true, namePattern: null }]);
  const removeSpec = (i: number) => onChange(specs.filter((_, idx) => idx !== i));
  const updateSpec = (i: number, field: string, value: unknown) =>
    onChange(specs.map((s, idx) => (idx === i ? { ...s, [field]: value } : s)));

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      {specs.length === 0 && <span style={{ fontSize: 12, color: 'var(--text-3)' }}>None added</span>}
      {specs.map((spec, idx) => (
        <div key={idx} style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          <input
            className={classes.descTa}
            style={{ flex: 1, height: 28, padding: '0 8px', lineHeight: '28px' }}
            placeholder="e.g. tasks/report.md"
            value={spec.name}
            onChange={(e) => updateSpec(idx, 'name', e.currentTarget.value)}
            disabled={disabled}
          />
          {showNamePattern && (
            <input
              className={classes.descTa}
              style={{ width: 100, height: 28, padding: '0 8px', lineHeight: '28px' }}
              placeholder="e.g. report"
              value={spec.namePattern ?? ''}
              onChange={(e) => updateSpec(idx, 'namePattern', e.currentTarget.value || null)}
              disabled={disabled}
            />
          )}
          <Switch
            size="xs"
            checked={spec.required}
            onChange={(e) => updateSpec(idx, 'required', e.currentTarget.checked)}
            disabled={disabled}
          />
          {!disabled && (
            <button type="button" className={classes.rowTrash} onClick={() => removeSpec(idx)} style={{ opacity: 1 }}>
              ×
            </button>
          )}
        </div>
      ))}
      {!disabled && (
        <button
          type="button"
          onClick={addSpec}
          style={{
            background: 'none',
            border: 'none',
            cursor: 'pointer',
            padding: '3px 0',
            display: 'inline-flex',
            alignItems: 'center',
            gap: 4,
            color: 'var(--accent-text)',
            fontSize: 12,
          }}
        >
          + Add {kind}
        </button>
      )}
    </div>
  );
}

const GROUP_PREFIX = 'grp:';

interface AgentModel {
  modelId: string;
  displayName: string;
}
interface AgentModelsEntry {
  agentType: string;
  models: AgentModel[];
}

interface SessionEditorPanelProps {
  step: Step;
  allSteps: Step[];
  agents: NamedItem[];
  tools: NamedItem[];
  toolGroups: ToolGroup[];
  skills: NamedItem[];
  mcpServers: NamedItem[];
  assets: NamedItem[];
  repositories: NamedItem[];
  agentModels?: AgentModelsEntry[];
  readOnly: boolean;
  onFieldChange: (field: string, value: unknown, immediate?: boolean) => void;
  onAssetSpecsChange: (field: 'inputAssetSpecs' | 'outputAssetSpecs', specs: AssetSpec[]) => void;
}

export function SessionEditorPanel({
  step,
  allSteps,
  agents,
  tools,
  toolGroups,
  skills,
  mcpServers,
  assets,
  repositories,
  agentModels = [],
  readOnly,
  onFieldChange,
  onAssetSpecsChange,
}: SessionEditorPanelProps) {
  const [instructionsExpanded, setInstructionsExpanded] = useState(false);
  const charCount = (step.instructions ?? '').length;

  const modelsMap: Record<string, AgentModel[]> = {};
  for (const entry of agentModels) modelsMap[entry.agentType] = entry.models;
  const runtimeModels = step.requiredAgentRuntime ? (modelsMap[step.requiredAgentRuntime] ?? []) : [];
  const modelOptions = runtimeModels
    .filter((m) => m.modelId)
    .map((m) => ({ value: m.modelId, label: m.displayName || m.modelId }));
  const preferredModelOptions =
    step.preferredModel && !modelOptions.some((o) => o.value === step.preferredModel)
      ? [...modelOptions, { value: step.preferredModel, label: step.preferredModel }]
      : modelOptions;

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

  const otherSessions = allSteps.filter((s) => s.id !== step.id);
  const dependencyOptions = otherSessions.map((s) => ({
    value: String(s.id),
    label: `${s.position}. ${s.name}`,
  }));

  const depNote =
    step.dependsOnStepIds.length === 0
      ? 'No dependencies — this session can run in parallel with other root sessions.'
      : `Waits for ${allSteps
          .filter((s) => step.dependsOnStepIds.includes(s.id))
          .map((s) => s.name)
          .join(', ')} to complete before starting.`;

  return (
    <div className={classes.editorPanel}>
      {/* ── DEFINITION ─────────────────────────────────────────────────────── */}
      <div className={classes.edSection}>
        <SectionLabel label="Definition" icon={<IconFileDescription size={14} />} />

        <input
          className={classes.stepNameInp}
          placeholder="Session name…"
          aria-label="Session name"
          value={step.name}
          onChange={(e) => onFieldChange('name', e.currentTarget.value)}
          disabled={readOnly}
        />

        <div style={{ marginTop: 12 }}>
          <label className={classes.fieldLabel}>
            Instructions
            <span className={classes.instrDot} title="Required" />
            <span
              className={classes.instrInfoIcon}
              title="The prompt the AI agent receives. Use {{artifact_name}} to reference assets."
            >
              <IconInfoCircle size={12} />
            </span>
          </label>
          <p className={classes.fieldHelp}>
            Use <code>{'{{artifact_name}}'}</code> to reference workflow assets.{' '}
            <a href="#" onClick={(e) => e.preventDefault()}>
              Prompt guide <IconArrowUpRight size={11} style={{ display: 'inline', verticalAlign: 'middle' }} />
            </a>
          </p>
          <textarea
            className={classes.instrTa}
            style={instructionsExpanded ? { minHeight: 400 } : undefined}
            placeholder="Enter instructions… Use {{artifact_name}} for variable references."
            aria-label="Session instructions"
            value={step.instructions ?? ''}
            onChange={(e) => onFieldChange('instructions', e.currentTarget.value)}
            disabled={readOnly}
          />
          <div className={classes.instrFoot}>
            <span className={classes.charCt}>{charCount} characters</span>
            <button className={classes.ibtn} type="button" onClick={() => setInstructionsExpanded((v) => !v)}>
              {instructionsExpanded ? <IconMinimize size={12} /> : <IconMaximize size={12} />}
              {instructionsExpanded ? 'Collapse' : 'Expand'}
            </button>
          </div>
        </div>
      </div>

      {/* ── EXECUTION ──────────────────────────────────────────────────────── */}
      <div className={classes.edSection}>
        <SectionLabel label="Execution" icon={<IconCpu size={14} />} />
        <div className={classes.field2Col}>
          <div>
            <label className={classes.fieldLabel}>
              Agent&nbsp;
              <span title="The AI model that executes this session" style={{ color: 'var(--text-3)', cursor: 'help' }}>
                <IconInfoCircle size={11} style={{ display: 'inline', verticalAlign: 'middle' }} />
              </span>
            </label>
            <Select
              data={[{ value: '', label: 'No agent' }, ...toSelectData(agents)]}
              value={step.agentId ? String(step.agentId) : ''}
              onChange={(v) => onFieldChange('agentId', v ? Number(v) : null, true)}
              disabled={readOnly}
              clearable
              placeholder="No agent"
              aria-label="Agent"
              styles={{
                input: {
                  background: 'transparent',
                  border: '1px solid var(--border)',
                  borderRadius: 4,
                  color: 'var(--text-1)',
                  fontSize: 13,
                },
              }}
            />
          </div>
          <div>
            <label className={classes.fieldLabel}>
              Execution Environment&nbsp;
              <span
                title="The CLI/runtime this session runs in. None uses the agent's default."
                style={{ color: 'var(--text-3)', cursor: 'help' }}
              >
                <IconInfoCircle size={11} style={{ display: 'inline', verticalAlign: 'middle' }} />
              </span>
            </label>
            <Select
              data={[
                { value: '', label: 'None (default)' },
                { value: 'claude_code', label: 'Claude Code' },
                { value: 'cursor_cli', label: 'Cursor CLI' },
                { value: 'codex', label: 'Codex' },
                { value: 'gemini_cli', label: 'Gemini CLI' },
              ]}
              value={step.requiredAgentRuntime ?? ''}
              onChange={(v) => {
                const runtime = v || null;
                if (runtime === step.requiredAgentRuntime) return;
                onFieldChange('requiredAgentRuntime', runtime, true);
                if (step.preferredModel) onFieldChange('preferredModel', null, true);
              }}
              disabled={readOnly}
              clearable
              placeholder="None (default)"
              aria-label="Required agent runtime"
              styles={{
                input: {
                  background: 'transparent',
                  border: '1px solid var(--border)',
                  borderRadius: 4,
                  color: 'var(--text-1)',
                  fontSize: 13,
                },
              }}
            />
          </div>
          {step.requiredAgentRuntime && (
            <div>
              <label className={classes.fieldLabel}>
                Preferred Model&nbsp;
                <span
                  title="Overrides the runtime's default model for this session."
                  style={{ color: 'var(--text-3)', cursor: 'help' }}
                >
                  <IconInfoCircle size={11} style={{ display: 'inline', verticalAlign: 'middle' }} />
                </span>
              </label>
              <Select
                data={preferredModelOptions}
                value={step.preferredModel ?? null}
                onChange={(v) => onFieldChange('preferredModel', v || null, true)}
                disabled={readOnly}
                clearable
                searchable
                placeholder="Default (runtime selects)"
                aria-label="Preferred model"
                styles={{
                  input: {
                    background: 'transparent',
                    border: '1px solid var(--border)',
                    borderRadius: 4,
                    color: 'var(--text-1)',
                    fontSize: 13,
                  },
                }}
              />
            </div>
          )}
        </div>
      </div>

      {/* ── RESOURCES ──────────────────────────────────────────────────────── */}
      <div className={classes.edSection}>
        <SectionLabel label="Resources" icon={<IconLayersIntersect size={14} />} />
        <div className={classes.infoNote}>
          <IconInfoCircle size={13} style={{ color: 'var(--accent-text)', flexShrink: 0 }} />
          Session-level additions — stacked on top of Base Resources
        </div>

        <div className={classes.resGroup}>
          <div className={classes.resType}>
            Tools <span className={classes.resTypeSub}>— custom functions this session can call</span>
          </div>
          <MultiSelect
            data={toolSelectData}
            value={toToolValue(step.toolIds)}
            onChange={(v) => onFieldChange('toolIds', fromToolValue(v), true)}
            disabled={readOnly}
            searchable
            placeholder="None added"
            aria-label="Tools"
            styles={{
              input: { background: 'transparent', border: '1px solid var(--border)', borderRadius: 4, fontSize: 13 },
            }}
          />
        </div>

        <div className={classes.resGroup}>
          <div className={classes.resType}>
            MCP Servers <span className={classes.resTypeSub}>— external providers</span>
          </div>
          <MultiSelect
            data={toSelectData(mcpServers)}
            value={toStringArr(step.mcpServerIds)}
            onChange={(v) => onFieldChange('mcpServerIds', toNumberArr(v), true)}
            disabled={readOnly}
            searchable
            placeholder="None added"
            aria-label="MCP servers"
            styles={{
              input: { background: 'transparent', border: '1px solid var(--border)', borderRadius: 4, fontSize: 13 },
            }}
          />
        </div>

        <div className={classes.resGroup}>
          <div className={classes.resType}>
            Skills <span className={classes.resTypeSub}>— capability modules</span>
          </div>
          <MultiSelect
            data={toSelectData(skills)}
            value={toStringArr(step.skillIds)}
            onChange={(v) => onFieldChange('skillIds', toNumberArr(v), true)}
            disabled={readOnly}
            searchable
            placeholder="None added"
            aria-label="Skills"
            styles={{
              input: { background: 'transparent', border: '1px solid var(--border)', borderRadius: 4, fontSize: 13 },
            }}
          />
        </div>

        <div className={classes.resGroup}>
          <div className={classes.resType}>
            Assets <span className={classes.resTypeSub}>— files loaded into /workspace/input</span>
          </div>
          <MultiSelect
            data={toSelectData(assets)}
            value={toStringArr(step.assetIds)}
            onChange={(v) => onFieldChange('assetIds', toNumberArr(v), true)}
            disabled={readOnly}
            searchable
            placeholder="None added"
            aria-label="Assets"
            styles={{
              input: { background: 'transparent', border: '1px solid var(--border)', borderRadius: 4, fontSize: 13 },
            }}
          />
        </div>

        <div className={classes.resGroup}>
          <div className={classes.resType}>
            Repositories <span className={classes.resTypeSub}>— cloned into /workspace/repo</span>
          </div>
          <MultiSelect
            data={toSelectData(repositories)}
            value={toStringArr(step.repositoryIds)}
            onChange={(v) => onFieldChange('repositoryIds', toNumberArr(v), true)}
            disabled={readOnly}
            searchable
            placeholder="None added"
            aria-label="Repositories"
            styles={{
              input: { background: 'transparent', border: '1px solid var(--border)', borderRadius: 4, fontSize: 13 },
            }}
          />
        </div>
      </div>

      {/* ── DEPENDENCIES ───────────────────────────────────────────────────── */}
      <div className={classes.edSection}>
        <SectionLabel label="Dependencies" icon={<IconListTree size={14} />} />
        <div className={classes.depNote}>
          <span
            style={{ width: 7, height: 7, borderRadius: '50%', background: 'var(--app-success-fg)', flexShrink: 0 }}
          />
          {depNote}
        </div>
        <label className={classes.fieldLabel}>
          Run after&nbsp;
          <span title="Waits for these sessions before starting" style={{ color: 'var(--text-3)', cursor: 'help' }}>
            <IconInfoCircle size={11} style={{ display: 'inline', verticalAlign: 'middle' }} />
          </span>
        </label>
        <MultiSelect
          data={dependencyOptions}
          value={toStringArr(step.dependsOnStepIds)}
          onChange={(v) => onFieldChange('dependsOnStepIds', toNumberArr(v), true)}
          disabled={readOnly}
          searchable
          placeholder="Select sessions this session depends on…"
          aria-label="Depends on sessions"
          styles={{
            input: { background: 'transparent', border: '1px solid var(--border)', borderRadius: 4, fontSize: 13 },
          }}
        />
      </div>

      {/* ── DATA FLOW ──────────────────────────────────────────────────────── */}
      <div className={classes.edSection}>
        <SectionLabel label="Data Flow" icon={<IconArrowsExchange2 size={14} />} />

        <div className={classes.dfGroup}>
          <div className={classes.dfSub}>
            Inputs <span className={classes.dfSubMuted}>— files this session reads</span>
          </div>
          <AssetRows
            specs={step.inputAssetSpecs ?? []}
            onChange={(specs) => onAssetSpecsChange('inputAssetSpecs', specs)}
            showNamePattern={false}
            disabled={readOnly}
            kind="input"
          />
        </div>

        <div className={classes.dfGroup}>
          <div className={classes.dfSub}>
            Output artifact <span className={classes.dfSubMuted}>— file this session produces</span>
          </div>
          <AssetRows
            specs={step.outputAssetSpecs ?? []}
            onChange={(specs) => onAssetSpecsChange('outputAssetSpecs', specs)}
            showNamePattern
            disabled={readOnly}
            kind="output"
          />
        </div>
      </div>

      {/* ── BEHAVIOR ───────────────────────────────────────────────────────── */}
      <div className={classes.edSection}>
        <SectionLabel label="Behavior" icon={<IconShield size={14} />} />

        <div className={classes.behGroup}>
          <div className={classes.behSub}>Run control</div>

          <div className={classes.togRow}>
            <div>
              <div className={classes.togLbl}>Auto-run available</div>
              <div className={classes.togDesc}>Skip user approval in non-interactive/mixed modes.</div>
            </div>
            <Switch
              checked={step.allowNonInteractive}
              onChange={(e) => onFieldChange('allowNonInteractive', e.currentTarget.checked, true)}
              disabled={readOnly}
            />
          </div>

          <div style={{ marginTop: 12 }}>
            <label className={classes.fieldLabel}>
              Skip Policy&nbsp;
              <span title="When to bypass this session during a run" style={{ color: 'var(--text-3)', cursor: 'help' }}>
                <IconInfoCircle size={11} style={{ display: 'inline', verticalAlign: 'middle' }} />
              </span>
            </label>
            <Select
              data={[
                { value: 'never', label: 'Never' },
                { value: 'if_outputs_exist', label: 'If outputs exist' },
                { value: 'manual', label: 'Manual' },
              ]}
              value={step.skipPolicy}
              onChange={(v) => onFieldChange('skipPolicy', v ?? 'never', true)}
              disabled={readOnly}
              allowDeselect={false}
              styles={{
                input: {
                  background: 'transparent',
                  border: '1px solid var(--border)',
                  borderRadius: 4,
                  color: 'var(--text-1)',
                  fontSize: 13,
                },
              }}
            />
            <div className={classes.consequence}>{SKIP_POLICY_TEXTS[step.skipPolicy] ?? ''}</div>
          </div>

          <div style={{ marginTop: 10 }}>
            <label className={classes.fieldLabel}>
              On Failure&nbsp;
              <span
                title="What happens when this session exits with an error"
                style={{ color: 'var(--text-3)', cursor: 'help' }}
              >
                <IconInfoCircle size={11} style={{ display: 'inline', verticalAlign: 'middle' }} />
              </span>
            </label>
            <Select
              data={[
                { value: 'fail', label: 'Fail' },
                { value: 'retry', label: 'Retry' },
                { value: 'skip', label: 'Skip' },
              ]}
              value={step.onFailure}
              onChange={(v) => onFieldChange('onFailure', v ?? 'fail', true)}
              disabled={readOnly}
              allowDeselect={false}
              styles={{
                input: {
                  background: 'transparent',
                  border: '1px solid var(--border)',
                  borderRadius: 4,
                  color: 'var(--text-1)',
                  fontSize: 13,
                },
              }}
            />
            <div className={classes.consequence}>{ON_FAILURE_TEXTS[step.onFailure] ?? ''}</div>
          </div>
        </div>

        <div className={classes.behGroup}>
          <div className={classes.behSub}>Environment</div>

          <div className={classes.togRow}>
            <div>
              <div className={classes.togLbl}>BMAD Method</div>
              <div className={classes.togDesc}>
                Enable the BMAD methodology for this session.{' '}
                <a href="#" style={{ color: 'var(--accent-text)' }} onClick={(e) => e.preventDefault()}>
                  Learn more ↗
                </a>
              </div>
            </div>
            <Switch
              checked={step.bmadEnabled}
              onChange={(e) => onFieldChange('bmadEnabled', e.currentTarget.checked, true)}
              disabled={readOnly}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
