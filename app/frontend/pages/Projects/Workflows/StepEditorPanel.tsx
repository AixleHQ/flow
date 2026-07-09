import { Switch } from '@mantine/core';
import { IconArrowUpRight, IconFileDescription, IconMaximize, IconShieldCheck } from '@tabler/icons-react';

import classes from './BuilderPage.module.css';

interface SubStep {
  id: number;
  name: string;
  description: string | null;
  instructions: string | null;
  position: number;
  required: boolean;
}

interface SectionLabelProps {
  label: string;
  icon: React.ReactNode;
}

function SectionLabel({ label, icon }: SectionLabelProps) {
  return (
    <div className={classes.secLabel}>
      <span className={classes.secLabelIcon}>{icon}</span>
      {label}
    </div>
  );
}

interface StepEditorPanelProps {
  step: SubStep;
  readOnly: boolean;
  onFieldChange: (field: string, value: unknown) => void;
}

export function StepEditorPanel({ step, readOnly, onFieldChange }: StepEditorPanelProps) {
  const instrLen = (step.instructions ?? '').length;

  return (
    <div className={classes.editorPanel}>
      {/* DEFINITION */}
      <div className={classes.edSection}>
        <SectionLabel label="Definition" icon={<IconFileDescription size={14} />} />

        {/* Name */}
        <input
          className={classes.stepNameInp}
          placeholder="Step name…"
          value={step.name}
          onChange={(e) => onFieldChange('name', e.currentTarget.value)}
          disabled={readOnly}
        />

        {/* Description */}
        <div style={{ marginTop: 10, marginBottom: 12 }}>
          <label className={classes.fieldLabel}>Description</label>
          <textarea
            className={classes.descTa}
            rows={2}
            placeholder="One-line summary of what this does…"
            value={step.description ?? ''}
            onChange={(e) => onFieldChange('description', e.currentTarget.value)}
            disabled={readOnly}
          />
        </div>

        {/* Instructions */}
        <div style={{ marginTop: 12 }}>
          <label className={classes.fieldLabel}>
            Instructions
            <span className={classes.instrDot} title="Required" />
          </label>
          <p className={classes.fieldHelp}>
            Use <code>{'{{artifact_name}}'}</code> to reference workflow assets.{' '}
            <a href="#" onClick={(e) => e.preventDefault()}>
              Prompt guide <IconArrowUpRight size={11} style={{ display: 'inline', verticalAlign: 'middle' }} />
            </a>
          </p>
          <textarea
            className={classes.instrTa}
            placeholder="Enter instructions… Use {{artifact_name}} for variable references."
            value={step.instructions ?? ''}
            onChange={(e) => onFieldChange('instructions', e.currentTarget.value)}
            disabled={readOnly}
          />
          <div className={classes.instrFoot}>
            <span className={classes.charCt}>{instrLen} characters</span>
            <button className={classes.ibtn} type="button" onClick={() => {}}>
              <IconMaximize size={12} />
              Expand
            </button>
          </div>
        </div>
      </div>

      {/* OPTIONS */}
      <div className={classes.edSection}>
        <SectionLabel label="Options" icon={<IconShieldCheck size={14} />} />
        <div className={classes.togRow}>
          <div>
            <div className={classes.togLbl}>Required</div>
            <div className={classes.togDesc}>Must complete for the parent session to proceed.</div>
          </div>
          <Switch
            checked={step.required}
            onChange={(e) => onFieldChange('required', e.currentTarget.checked)}
            disabled={readOnly}
          />
        </div>
      </div>
    </div>
  );
}
