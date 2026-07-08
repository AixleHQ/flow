import { Box, Stack, Switch, Text, Textarea, TextInput } from '@mantine/core';

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
}

function SectionLabel({ label }: SectionLabelProps) {
  return (
    <Box pb={8} mb={12} style={{ borderBottom: '1px solid var(--border)' }}>
      <Text size="xs" fw={700} style={{ color: 'var(--text-2)', textTransform: 'uppercase', letterSpacing: '0.1em' }}>
        {label}
      </Text>
    </Box>
  );
}

interface StepEditorPanelProps {
  step: SubStep;
  readOnly: boolean;
  onFieldChange: (field: string, value: unknown) => void;
}

export function StepEditorPanel({ step, readOnly, onFieldChange }: StepEditorPanelProps) {
  return (
    <div className={classes.editorPanel}>
      {/* DEFINITION */}
      <Box mb={24}>
        <SectionLabel label="Definition" />

        <TextInput
          placeholder="Step name…"
          value={step.name}
          onChange={(e) => onFieldChange('name', e.currentTarget.value)}
          disabled={readOnly}
          variant="unstyled"
          styles={{
            input: {
              fontSize: 18,
              fontWeight: 700,
              fontFamily: 'Sora, sans-serif',
              color: 'var(--text-1)',
              padding: '4px 0',
              borderBottom: '1px solid transparent',
              borderRadius: 0,
            },
          }}
          mb={12}
        />

        <Textarea
          placeholder="One-line summary of what this does…"
          value={step.description ?? ''}
          onChange={(e) => onFieldChange('description', e.currentTarget.value)}
          disabled={readOnly}
          autosize
          minRows={2}
          mb={16}
          styles={{ input: { background: 'transparent', border: '1px solid var(--border)', borderRadius: 4 } }}
        />

        <Textarea
          label="Instructions"
          placeholder="Enter step instructions…"
          value={step.instructions ?? ''}
          onChange={(e) => onFieldChange('instructions', e.currentTarget.value)}
          disabled={readOnly}
          autosize
          minRows={4}
          styles={{ input: { background: 'transparent', border: '1px solid var(--border)', borderRadius: 4 } }}
        />
      </Box>

      {/* OPTIONS */}
      <Box mb={24}>
        <SectionLabel label="Options" />
        <Stack gap="sm">
          <Switch
            label="Required"
            description="Must complete for the parent session to proceed."
            checked={step.required}
            onChange={(e) => onFieldChange('required', e.currentTarget.checked)}
            disabled={readOnly}
          />
        </Stack>
      </Box>
    </div>
  );
}
