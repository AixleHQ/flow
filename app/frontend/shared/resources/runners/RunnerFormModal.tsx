import type { FormDataConvertible } from '@inertiajs/core';
import { router } from '@inertiajs/react';
import { Alert, Button, Group, Modal, NumberInput, Radio, Stack, Stepper, Text, TextInput } from '@mantine/core';
import { IconAlertCircle } from '@tabler/icons-react';
import { useEffect, useMemo, useState } from 'react';

import type { Runner } from '@/types/generated';

import { useConfirmClose } from 'shared/lib/hooks/useConfirmClose';

import {
  ACKNOWLEDGED_MOUNTS_PATH,
  acknowledgedMounts,
  configForSubmit,
  errorMessages,
  humanize,
  pathKey,
  placeConfigErrors,
  schemaAt,
  writableHostMounts,
  type RunnerConfig,
  type RunnerPaths,
  type RunnerTypeOption,
} from './runnerConfig';
import { DEFAULT_REUSE_POLICY, REUSE_POLICY_COPY, RUNNER_TYPE_COPY, runnerTypeTitle } from './runnerCopy';
import { SchemaFields } from './SchemaFields';

type Step = 'type' | 'config' | 'limits';

const STEP_LABELS: Record<Step, string> = { type: 'Type', config: 'Configuration', limits: 'Limits' };

interface FormErrors {
  /** Per field: `name`, `max_concurrency`, `reuse_policy`, `runner_type`, or a config path. */
  fields: Record<string, string[]>;
  /** Messages that belong to no field, shown above the form. */
  general: string[];
}

const NO_ERRORS: FormErrors = { fields: {}, general: [] };

// The server's attributes, by the step whose fields show them. Inertia may hand them over
// camelized, so both spellings are read.
const ATTRIBUTE_STEPS: { attribute: string; camel: string; step: Step }[] = [
  { attribute: 'runner_type', camel: 'runnerType', step: 'type' },
  { attribute: 'reuse_policy', camel: 'reusePolicy', step: 'config' },
  { attribute: 'name', camel: 'name', step: 'limits' },
  { attribute: 'max_concurrency', camel: 'maxConcurrency', step: 'limits' },
  { attribute: 'max_environments', camel: 'maxEnvironments', step: 'limits' },
];

interface RunnerFormModalProps {
  opened: boolean;
  onClose: () => void;
  runnerTypes: RunnerTypeOption[];
  paths: RunnerPaths;
  /** The runner to edit. Without one the form creates a runner, starting from the type. */
  runner?: Runner | null;
}

interface Draft {
  runnerType: string | null;
  config: RunnerConfig;
  name: string;
  maxConcurrency: number | '';
  maxEnvironments: number | '';
  reusePolicy: Runner['reusePolicy'] | null;
}

const draftFor = (runner?: Runner | null): Draft => ({
  runnerType: runner?.runnerType ?? null,
  config: runner?.config ?? {},
  name: runner?.name ?? '',
  maxConcurrency: runner?.maxConcurrency ?? 1,
  maxEnvironments: runner?.maxEnvironments ?? '',
  // On create an untouched policy is not sent: the server defaults it by type.
  reusePolicy: runner?.reusePolicy ?? null,
});

export function RunnerFormModal({ opened, onClose, runnerTypes, paths, runner }: RunnerFormModalProps) {
  const editing = !!runner;
  const steps: Step[] = editing ? ['config', 'limits'] : ['type', 'config', 'limits'];
  const [active, setActive] = useState(0);
  const [draft, setDraft] = useState<Draft>(() => draftFor(runner));
  const [errors, setErrors] = useState<FormErrors>(NO_ERRORS);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (opened) {
      setActive(0);
      setDraft(draftFor(runner));
      setErrors(NO_ERRORS);
    }
  }, [opened, runner]);

  const option = runnerTypes.find((t) => t.runnerType === draft.runnerType);
  const schema = useMemo(() => option?.configSchema ?? {}, [option]);
  const provisionable = option?.capabilities.provisionable ?? false;
  const dirty = JSON.stringify(draft) !== JSON.stringify(draftFor(runner));
  const requestClose = useConfirmClose(dirty, onClose);

  const update = (changes: Partial<Draft>) => setDraft((current) => ({ ...current, ...changes }));
  const step = steps[active];
  const fieldError = (key: string) => {
    const messages = errors.fields[key];
    return messages && messages.length > 0 ? messages.join(' ') : undefined;
  };

  const showErrors = (next: FormErrors) => {
    setErrors(next);
    const first = steps.findIndex((s) =>
      Object.keys(next.fields).some((field) => stepOfField(field) === s && next.fields[field].length > 0),
    );
    if (first !== -1) setActive(first);
  };

  const receiveServerErrors = (received: Record<string, unknown>) => {
    const next: FormErrors = { fields: {}, general: [] };
    const handled = new Set<string>(['config']);

    ATTRIBUTE_STEPS.forEach(({ attribute, camel, step: attributeStep }) => {
      handled.add(attribute).add(camel);
      const unique = [...new Set(errorMessages(received, ...new Set([attribute, camel])))];
      if (unique.length === 0) return;
      if (steps.includes(attributeStep)) next.fields[attribute] = unique;
      else next.general.push(...unique.map((message) => `${humanize(attribute)} ${message}`));
    });

    const placed = placeConfigErrors(errorMessages(received, 'config'), schema);
    Object.assign(next.fields, placed.byField);
    next.general.push(...placed.unplaced);

    Object.keys(received)
      .filter((key) => !handled.has(key))
      .forEach((key) => next.general.push(...errorMessages(received, key).map((m) => `${humanize(key)} ${m}`)));

    showErrors(next);
  };

  const localErrors = (): FormErrors => {
    const fields: Record<string, string[]> = {};
    if (schemaAt(schema, ACKNOWLEDGED_MOUNTS_PATH)) {
      const missing = writableHostMounts(draft.config).filter((m) => !acknowledgedMounts(draft.config).includes(m));
      if (missing.length > 0) {
        fields[pathKey(ACKNOWLEDGED_MOUNTS_PATH)] = [`Acknowledge every writable host mount: ${missing.join(', ')}`];
      }
    }
    if (draft.name.trim() === '') fields.name = ['Name is required'];
    if (draft.maxConcurrency === '') fields.max_concurrency = ['Max concurrency is required'];
    return { fields, general: [] };
  };

  const submit = () => {
    const local = localErrors();
    if (Object.keys(local.fields).length > 0) {
      showErrors(local);
      return;
    }

    const body: Record<string, FormDataConvertible> = {
      name: draft.name.trim(),
      max_concurrency: draft.maxConcurrency,
      max_environments: provisionable && draft.maxEnvironments !== '' ? draft.maxEnvironments : null,
      config: configForSubmit(draft.config, schema) as Record<string, FormDataConvertible>,
    };
    if (!editing) body.runner_type = draft.runnerType;
    if (draft.reusePolicy) body.reuse_policy = draft.reusePolicy;

    const options = {
      preserveScroll: true,
      // A refused create comes back to this page: keep the form open with what was entered.
      preserveState: true,
      onSuccess: () => onClose(),
      onError: (received: Record<string, unknown>) => receiveServerErrors(received),
      onFinish: () => setSubmitting(false),
    };

    setSubmitting(true);
    setErrors(NO_ERRORS);
    if (runner) router.patch(paths.runner(runner.id), { runner: body }, options);
    else router.post(paths.list, { runner: body }, options);
  };

  const reuseCopy = draft.runnerType ? REUSE_POLICY_COPY[draft.runnerType as Runner['runnerType']] : undefined;
  const defaultReuse = draft.runnerType ? DEFAULT_REUSE_POLICY[draft.runnerType as Runner['runnerType']] : undefined;
  const isLast = active === steps.length - 1;
  const canAdvance = step !== 'type' || !!option;

  return (
    <Modal
      opened={opened}
      onClose={requestClose}
      size="xl"
      title={<Text fw={600}>{runner ? `Edit ${runner.name}` : 'New runner'}</Text>}
    >
      <Stack gap="lg">
        <Stepper active={active} onStepClick={(index) => index < active && setActive(index)} size="xs">
          {steps.map((s) => (
            <Stepper.Step key={s} label={STEP_LABELS[s]} />
          ))}
        </Stepper>

        {errors.general.length > 0 && (
          <Alert color="red" variant="light" icon={<IconAlertCircle size={16} />} title="The runner was not saved">
            <Stack gap={2}>
              {errors.general.map((message) => (
                <Text key={message} fz="sm">
                  {message}
                </Text>
              ))}
            </Stack>
          </Alert>
        )}

        {step === 'type' && (
          <Radio.Group
            label="Runner type"
            description="Where sessions on this runner run."
            value={draft.runnerType}
            error={fieldError('runner_type')}
            onChange={(value) => update({ runnerType: value, config: {}, reusePolicy: null })}
          >
            <Stack gap="xs" mt="xs">
              {runnerTypes.map((type) => (
                <Radio.Card
                  key={type.runnerType}
                  value={type.runnerType}
                  radius="md"
                  p="md"
                  aria-label={runnerTypeTitle(type.runnerType)}
                >
                  <Group wrap="nowrap" align="flex-start" gap="sm">
                    <Radio.Indicator mt={2} />
                    <div>
                      <Text fw={600} fz="sm">
                        {runnerTypeTitle(type.runnerType)}
                      </Text>
                      {RUNNER_TYPE_COPY[type.runnerType] && (
                        <Text fz="sm" c="dimmed">
                          {RUNNER_TYPE_COPY[type.runnerType].description}
                        </Text>
                      )}
                    </div>
                  </Group>
                </Radio.Card>
              ))}
            </Stack>
          </Radio.Group>
        )}

        {step === 'config' && option && (
          <Stack gap="lg">
            <SchemaFields
              schema={schema}
              config={draft.config}
              onChange={(config) => update({ config })}
              errors={errors.fields}
            />
            <Radio.Group
              label="Reuse policy"
              value={draft.reusePolicy ?? defaultReuse ?? null}
              error={fieldError('reuse_policy')}
              onChange={(value) => update({ reusePolicy: value as Runner['reusePolicy'] })}
            >
              <Stack gap="xs" mt="xs">
                {(['reuse', 'fresh'] as const).map((policy) => (
                  <Radio
                    key={policy}
                    value={policy}
                    label={policy === defaultReuse ? `${humanize(policy)} (default)` : humanize(policy)}
                    description={reuseCopy?.[policy]}
                  />
                ))}
              </Stack>
            </Radio.Group>
          </Stack>
        )}

        {step === 'limits' && (
          <Stack gap="md">
            <TextInput
              label="Name"
              required
              value={draft.name}
              error={fieldError('name')}
              onChange={(event) => update({ name: event.currentTarget.value })}
            />
            <NumberInput
              label="Max concurrency"
              description="How many sessions may run on this runner at once."
              required
              min={1}
              allowDecimal={false}
              value={draft.maxConcurrency}
              error={fieldError('max_concurrency')}
              onChange={(value) => update({ maxConcurrency: typeof value === 'number' ? value : '' })}
            />
            {provisionable ? (
              <NumberInput
                label="Max environments"
                description="How many environments this runner may provision. Empty means the same as max concurrency."
                min={1}
                allowDecimal={false}
                value={draft.maxEnvironments}
                error={fieldError('max_environments')}
                onChange={(value) => update({ maxEnvironments: typeof value === 'number' ? value : '' })}
              />
            ) : (
              <Text fz="sm" c="dimmed">
                Max environments does not apply to a {runnerTypeTitle(draft.runnerType ?? '').toLowerCase()} runner:
                each machine you connect is one environment.
              </Text>
            )}
            {fieldError('max_environments') && !provisionable && (
              <Text fz="sm" c="red">
                {fieldError('max_environments')}
              </Text>
            )}
          </Stack>
        )}

        <Group justify="space-between">
          <Button variant="default" onClick={() => (active === 0 ? requestClose() : setActive(active - 1))}>
            {active === 0 ? 'Cancel' : 'Back'}
          </Button>
          {isLast ? (
            <Button onClick={submit} loading={submitting}>
              {runner ? 'Save runner' : 'Create runner'}
            </Button>
          ) : (
            <Button onClick={() => setActive(active + 1)} disabled={!canAdvance}>
              Next
            </Button>
          )}
        </Group>
      </Stack>
    </Modal>
  );
}

const LIMIT_FIELDS = new Set(['name', 'max_concurrency', 'max_environments']);

function stepOfField(field: string): Step {
  if (field === 'runner_type') return 'type';
  if (LIMIT_FIELDS.has(field)) return 'limits';
  return 'config';
}
