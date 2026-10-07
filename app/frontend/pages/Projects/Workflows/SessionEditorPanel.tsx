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
import { useRef, useState } from 'react';

import type { ConfigItemPicker, Step } from '@/types/generated';

import { AssetPicker, type AssetPickerItem } from 'shared/components/AssetPicker';
import { ReferenceEditor, type ReferenceItem } from 'shared/components/ReferenceEditor/ReferenceEditor';
import { ToolPicker } from 'shared/components/ToolPicker';
import { type ToolGroup } from 'shared/lib/toolPicker';
import { AGENT_SELECT_OPTIONS } from 'shared/ui/agentRuntimes';

import classes from './BuilderPage.module.css';
import { type IssueFix, normalizeSpecName, type WorkflowIssue } from './dataFlow';
import { IssueList } from './IssueList';
import { type AvailableInput, REFERENCE_GROUPS } from './referenceCatalog';

interface NamedItem {
  id: number;
  name: string;
}

type AssetSpec = Step['outputAssetSpecs'][number];

type SessionStep = Pick<
  Step,
  | 'id'
  | 'name'
  | 'instructions'
  | 'position'
  | 'agentId'
  | 'requiredAgentRuntime'
  | 'preferredModel'
  | 'allowNonInteractive'
  | 'skipPolicy'
  | 'onFailure'
  | 'bmadEnabled'
  | 'dependsOnStepIds'
  | 'toolIds'
  | 'mcpServerIds'
  | 'skillIds'
  | 'assetIds'
  | 'repositoryIds'
  | 'configItemIds'
  | 'inputAssetSpecs'
  | 'outputAssetSpecs'
>;

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
  placeholder: string;
  /** A name that was edited and left, already normalized: `before` is what it was on focus. */
  onNameCommitted?: (before: string, after: string) => void;
}

function AssetRows({ specs, onChange, showNamePattern, disabled, kind, placeholder, onNameCommitted }: AssetRowsProps) {
  const namesOnFocus = useRef<Record<number, string>>({});
  const addSpec = () => onChange([...specs, { name: '', assetType: 'file', required: true, namePattern: null }]);
  const removeSpec = (i: number) => onChange(specs.filter((_, idx) => idx !== i));
  const updateSpec = (i: number, field: string, value: unknown) =>
    onChange(specs.map((s, idx) => (idx === i ? { ...s, [field]: value } : s)));
  const commitName = (i: number) => {
    const current = specs[i]?.name ?? '';
    const normalized = normalizeSpecName(current);
    if (normalized !== current) updateSpec(i, 'name', normalized);
    const before = namesOnFocus.current[i] ?? current;
    delete namesOnFocus.current[i];
    if (before !== normalized) onNameCommitted?.(before, normalized);
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      {specs.length === 0 && <span style={{ fontSize: 12, color: 'var(--text-3)' }}>None added</span>}
      {specs.map((spec, idx) => (
        <div key={idx} style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          <input
            className={classes.descTa}
            style={{ flex: 1, height: 28, padding: '0 8px', lineHeight: '28px' }}
            placeholder={placeholder}
            aria-label={`${kind === 'input' ? 'Input' : 'Output'} ${idx + 1} name`}
            value={spec.name}
            onFocus={() => {
              namesOnFocus.current[idx] = spec.name;
            }}
            onChange={(e) => updateSpec(idx, 'name', e.currentTarget.value)}
            onBlur={() => commitName(idx)}
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

interface AgentModel {
  modelId: string;
  displayName: string;
}
interface AgentModelsEntry {
  agentType: string;
  models: AgentModel[];
}

interface SessionEditorPanelProps {
  step: SessionStep;
  allSteps: SessionStep[];
  agents: NamedItem[];
  tools: NamedItem[];
  toolGroups: ToolGroup[];
  skills: NamedItem[];
  mcpServers: NamedItem[];
  assets: AssetPickerItem[];
  repositories: NamedItem[];
  configItems: ConfigItemPicker[];
  agentModels?: AgentModelsEntry[];
  readOnly: boolean;
  onFieldChange: (field: string, value: unknown) => void;
  onAssetSpecsChange: (field: 'inputAssetSpecs' | 'outputAssetSpecs', specs: AssetSpec[]) => void;
  /** What `@` offers in the instructions, and whether the deferred catalog is still loading. */
  references: { items: ReferenceItem[]; loading: boolean };
  onInsertReference: (item: ReferenceItem) => void;
  /** This session's data-flow issues. */
  issues: WorkflowIssue[];
  fixLabel: (fix: IssueFix) => string | null;
  onFix: (fix: IssueFix) => void;
  /** Files this session can count on when it starts. */
  available: AvailableInput[];
  onOutputRenamed: (before: string, after: string) => void;
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
  configItems,
  agentModels = [],
  readOnly,
  onFieldChange,
  onAssetSpecsChange,
  references,
  onInsertReference,
  issues,
  fixLabel,
  onFix,
  available,
  onOutputRenamed,
}: SessionEditorPanelProps) {
  const issuesFor = (field: WorkflowIssue['field']) => issues.filter((issue) => issue.field === field);
  const issueFix = readOnly ? () => null : fixLabel;
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

  const stepConfigItemIds = step.configItemIds ?? [];
  const configItemSelectData = (Array.isArray(configItems) ? configItems : [])
    .filter((c) => c?.id != null)
    .map((c) => ({ value: String(c.id), label: c.itemType === 'secret' ? `${c.name} (secret)` : c.name }));

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
              title="The prompt the AI agent receives. Each @ reference becomes the real path or name."
            >
              <IconInfoCircle size={12} />
            </span>
          </label>
          <p className={classes.fieldHelp}>
            Type <code>@</code> to reference an asset, another session, an output or an MCP server. The agent gets the
            real path or name.{' '}
            <a href="/docs/prompt-guide" target="_blank" rel="noopener noreferrer">
              Prompt guide <IconArrowUpRight size={11} style={{ display: 'inline', verticalAlign: 'middle' }} />
            </a>
          </p>
          <ReferenceEditor
            value={step.instructions ?? ''}
            onChange={(value) => onFieldChange('instructions', value)}
            items={references.items}
            groups={REFERENCE_GROUPS}
            loading={references.loading}
            readOnly={readOnly}
            onInsert={onInsertReference}
            placeholder="Enter instructions… Type @ to reference assets, sessions, outputs or connections."
            ariaLabel="Session instructions"
            minHeight={instructionsExpanded ? 400 : 180}
            maxHeight={instructionsExpanded ? null : 620}
          />
          <IssueList
            issues={issuesFor('instructions')}
            fixLabel={issueFix}
            onFix={onFix}
            label="Problems in the instructions"
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
              onChange={(v) => onFieldChange('agentId', v ? Number(v) : null)}
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
              data={[{ value: '', label: 'None (default)' }, ...AGENT_SELECT_OPTIONS]}
              value={step.requiredAgentRuntime ?? ''}
              onChange={(v) => {
                const runtime = v || null;
                if (runtime === step.requiredAgentRuntime) return;
                onFieldChange('requiredAgentRuntime', runtime);
                if (step.preferredModel) onFieldChange('preferredModel', null);
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
                onChange={(v) => onFieldChange('preferredModel', v || null)}
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
          <ToolPicker
            tools={tools}
            groups={toolGroups}
            value={step.toolIds}
            onChange={(ids) => onFieldChange('toolIds', ids)}
            disabled={readOnly}
            placeholder="None added"
            aria-label="Tools"
            inputStyles={{
              background: 'transparent',
              border: '1px solid var(--border)',
              borderRadius: 4,
              fontSize: 13,
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
            onChange={(v) => onFieldChange('mcpServerIds', toNumberArr(v))}
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
            onChange={(v) => onFieldChange('skillIds', toNumberArr(v))}
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
            Assets <span className={classes.resTypeSub}>— files loaded into /workspace/assets</span>
          </div>
          <AssetPicker
            assets={assets}
            value={step.assetIds}
            onChange={(ids) => onFieldChange('assetIds', ids)}
            disabled={readOnly}
            placeholder="None added"
            aria-label="Assets"
          />
        </div>

        <div className={classes.resGroup}>
          <div className={classes.resType}>
            Secrets &amp; Variables <span className={classes.resTypeSub}>— read on demand with get_config_item</span>
          </div>
          <MultiSelect
            data={configItemSelectData}
            value={toStringArr(stepConfigItemIds)}
            onChange={(v) => onFieldChange('configItemIds', toNumberArr(v))}
            disabled={readOnly}
            searchable
            placeholder="None added"
            aria-label="Secrets and variables"
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
            onChange={(v) => onFieldChange('repositoryIds', toNumberArr(v))}
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
          onChange={(v) => onFieldChange('dependsOnStepIds', toNumberArr(v))}
          disabled={readOnly}
          searchable
          placeholder="Select sessions this session depends on…"
          aria-label="Depends on sessions"
          styles={{
            input: { background: 'transparent', border: '1px solid var(--border)', borderRadius: 4, fontSize: 13 },
          }}
        />
        <IssueList
          issues={issuesFor('dependsOnStepIds')}
          fixLabel={issueFix}
          onFix={onFix}
          label="Problems with dependencies"
        />
      </div>

      {/* ── DATA FLOW ──────────────────────────────────────────────────────── */}
      <div className={classes.edSection}>
        <SectionLabel label="Data Flow" icon={<IconArrowsExchange2 size={14} />} />

        <div className={classes.dfGroup}>
          <div className={classes.dfSub}>
            Available when this session starts <span className={classes.dfSubMuted}>— in /workspace/assets</span>
          </div>
          {available.length === 0 ? (
            <span style={{ fontSize: 12, color: 'var(--text-3)' }}>Nothing yet</span>
          ) : (
            <ul className={classes.availableList} aria-label="Available when this session starts">
              {available.map((input, index) => (
                <li key={`${input.source}-${input.name}-${index}`}>
                  <code>{input.name}</code> <span className={classes.availableSource}>← {input.source}</span>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className={classes.dfGroup}>
          <div className={classes.dfSub}>
            Inputs <span className={classes.dfSubMuted}>— files this session needs</span>
          </div>
          <p className={classes.dfHelp}>
            Needed only for files picked when a run starts. Files referenced with @ are checked automatically.
          </p>
          <AssetRows
            specs={step.inputAssetSpecs ?? []}
            onChange={(specs) => onAssetSpecsChange('inputAssetSpecs', specs)}
            showNamePattern={false}
            disabled={readOnly}
            kind="input"
            placeholder="e.g. report.md"
          />
          <IssueList
            issues={issuesFor('inputAssetSpecs')}
            fixLabel={issueFix}
            onFix={onFix}
            label="Problems with inputs"
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
            placeholder="e.g. report.md or reports/*.md"
            onNameCommitted={onOutputRenamed}
          />
          <IssueList
            issues={issuesFor('outputAssetSpecs')}
            fixLabel={issueFix}
            onFix={onFix}
            label="Problems with outputs"
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
              onChange={(e) => onFieldChange('allowNonInteractive', e.currentTarget.checked)}
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
              onChange={(v) => onFieldChange('skipPolicy', v ?? 'never')}
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
              onChange={(v) => onFieldChange('onFailure', v ?? 'fail')}
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
                <a
                  href="https://docs.bmad-method.org/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className={classes.learnMoreLink}
                >
                  Learn more <IconArrowUpRight size={11} style={{ display: 'inline', verticalAlign: 'middle' }} />
                </a>
              </div>
            </div>
            <Switch
              checked={step.bmadEnabled}
              onChange={(e) => onFieldChange('bmadEnabled', e.currentTarget.checked)}
              disabled={readOnly}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
