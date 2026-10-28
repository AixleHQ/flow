import {
  ActionIcon,
  Alert,
  Box,
  Button,
  Checkbox,
  Fieldset,
  Group,
  Input,
  NumberInput,
  Radio,
  Stack,
  Switch,
  TagsInput,
  Text,
  TextInput,
  Textarea,
} from '@mantine/core';
import { IconAlertTriangle, IconPlus, IconTrash } from '@tabler/icons-react';
import { useState, type ReactNode } from 'react';

import { FIELD_COPY, FIELD_ORDER, fieldLabel } from './runnerCopy';
import {
  ACKNOWLEDGED_MOUNTS_PATH,
  DOCKER_SOCKET_PATH,
  PRIVILEGED_MOUNTS_PATH,
  acknowledgedMounts,
  getAt,
  humanize,
  pathKey,
  schemaAt,
  schemaTypes,
  setAt,
  writableHostMounts,
  type JsonSchema,
  type RunnerConfig,
} from './runnerConfig';

/*
 * An in-house renderer for the JSON Schema of Runners::ConfigSchema: objects (groups and the
 * nullable `home_mount`), booleans, enums, numbers, strings, lists of strings and lists of objects,
 * with a raw-JSON field for any other shape. A JSON Schema form library would bring its own form
 * state and widgets to restyle to Mantine, and would still need the overrides below: the
 * acknowledgement and the Docker-socket rule are §2.7/§6.8 rules, not schema keywords.
 *
 * A key the user has not set is absent from `config`, and its field shows the schema's default.
 */

interface SchemaFieldsProps {
  schema: JsonSchema;
  config: RunnerConfig;
  onChange: (config: RunnerConfig) => void;
  /** Messages per field path (`container.network`), the server's and the form's own. */
  errors: Record<string, string[]>;
}

const formatDefault = (value: unknown): string => {
  if (value === true) return 'on';
  if (value === false) return 'off';
  if (value === null || value === undefined || (Array.isArray(value) && value.length === 0)) return 'none';
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
};

const orderedProperties = (schema: JsonSchema, prefix: string[]): [string, JsonSchema][] => {
  const rank = (name: string) => {
    const index = FIELD_ORDER.indexOf(pathKey([...prefix, name]));
    return index === -1 ? FIELD_ORDER.length : index;
  };
  return Object.entries(schema.properties ?? {}).sort(([a], [b]) => rank(a) - rank(b));
};

const joinErrors = (messages: string[] | undefined): string | undefined =>
  messages && messages.length > 0 ? messages.join(' ') : undefined;

export function SchemaFields({ schema, config, onChange, errors }: SchemaFieldsProps) {
  const set = (path: string[], value: unknown) => {
    let next = setAt(config, schema, path, value);
    // The socket needs the gate (§6.8): closing the gate turns the socket off with it.
    if (pathKey(path) === pathKey(PRIVILEGED_MOUNTS_PATH) && value !== true && getAt(next, DOCKER_SOCKET_PATH)) {
      next = setAt(next, schema, DOCKER_SOCKET_PATH, undefined);
    }
    onChange(next);
  };

  const field = (path: string[], propertySchema: JsonSchema): ReactNode => {
    const key = pathKey(path);
    const props: FieldProps = {
      path,
      schema: propertySchema,
      value: getAt(config, path),
      isSet: getAt(config, path) !== undefined,
      onChange: (value) => set(path, value),
      error: joinErrors(errors[key]),
    };

    if (key === pathKey(ACKNOWLEDGED_MOUNTS_PATH)) return <AcknowledgementField key={key} {...props} config={config} />;
    if (key === pathKey(DOCKER_SOCKET_PATH)) {
      const gate = getAt(config, PRIVILEGED_MOUNTS_PATH) ?? schemaAt(schema, PRIVILEGED_MOUNTS_PATH)?.default;
      return <DockerSocketField key={key} {...props} allowed={gate === true} />;
    }

    const types = schemaTypes(propertySchema);
    if (propertySchema.properties && types.includes('null')) {
      return (
        <NullableObjectField key={key} {...props}>
          {orderedProperties(propertySchema, path).map(([name, child]) => field([...path, name], child))}
        </NullableObjectField>
      );
    }
    if (propertySchema.properties) {
      return (
        <Fieldset key={key} legend={fieldLabel(key)} radius="md">
          <Stack gap="md">
            {FIELD_COPY[key]?.description && (
              <Text fz="sm" c="dimmed">
                {FIELD_COPY[key].description}
              </Text>
            )}
            {joinErrors(errors[key]) && <Input.Error>{joinErrors(errors[key])}</Input.Error>}
            {orderedProperties(propertySchema, path).map(([name, child]) => field([...path, name], child))}
          </Stack>
        </Fieldset>
      );
    }
    return <LeafField key={key} {...props} />;
  };

  return <Stack gap="lg">{orderedProperties(schema, []).map(([name, child]) => field([name], child))}</Stack>;
}

interface FieldProps {
  path: string[];
  schema: JsonSchema;
  value: unknown;
  isSet: boolean;
  onChange: (value: unknown) => void;
  error?: string;
}

/** The field's words, what it defaults to while unset, and a way back to that default once set. */
function FieldDescription({
  path,
  schema,
  isSet,
  onChange,
}: Pick<FieldProps, 'path' | 'schema' | 'isSet' | 'onChange'>) {
  const key = pathKey(path);
  const description = FIELD_COPY[key]?.description;
  const hasDefault = schema.default !== undefined;

  if (!description && !hasDefault) return null;
  return (
    <Group gap={6} component="span" wrap="wrap">
      {description && <span>{description}</span>}
      {hasDefault && !isSet && <span>Default: {formatDefault(schema.default)}.</span>}
      {hasDefault && isSet && (
        <Button
          variant="subtle"
          size="compact-xs"
          onClick={() => onChange(undefined)}
          aria-label={`Use the default for ${fieldLabel(key)}`}
        >
          Use default ({formatDefault(schema.default)})
        </Button>
      )}
    </Group>
  );
}

function LeafField(props: FieldProps) {
  const { path, schema, value, onChange, error } = props;
  const key = pathKey(path);
  const label = fieldLabel(key);
  const description = <FieldDescription {...props} />;
  const types = schemaTypes(schema);
  const shown = value === undefined ? schema.default : value;

  if (schema.enum) {
    return (
      <Radio.Group
        label={label}
        description={description}
        error={error}
        value={shown === undefined ? null : String(shown)}
        onChange={(next) => onChange(schema.enum?.find((option) => String(option) === next))}
      >
        <Group gap="lg" mt={6}>
          {schema.enum.map((option) => (
            <Radio
              key={String(option)}
              value={String(option)}
              label={option === schema.default ? `${String(option)} (default)` : String(option)}
            />
          ))}
        </Group>
      </Radio.Group>
    );
  }

  if (types.includes('boolean')) {
    return (
      <Switch
        label={label}
        description={description}
        error={error}
        checked={shown === true}
        onChange={(event) => onChange(event.currentTarget.checked)}
      />
    );
  }

  if (types.includes('integer') || types.includes('number')) {
    return (
      <NumberInput
        label={label}
        description={description}
        error={error}
        value={typeof value === 'number' ? value : ''}
        placeholder={schema.default !== undefined ? String(schema.default) : undefined}
        min={schema.minimum}
        max={schema.maximum}
        allowDecimal={!types.includes('integer')}
        onChange={(next) => onChange(typeof next === 'number' ? next : undefined)}
      />
    );
  }

  if (types.includes('string')) {
    return (
      <TextInput
        label={label}
        description={description}
        error={error}
        value={typeof value === 'string' ? value : ''}
        placeholder={typeof schema.default === 'string' ? schema.default : undefined}
        onChange={(event) => onChange(event.currentTarget.value === '' ? undefined : event.currentTarget.value)}
      />
    );
  }

  if (types.includes('array') && schema.items?.properties) return <ObjectListField {...props} />;

  if (types.includes('array') && schemaTypes(schema.items ?? {}).includes('string')) {
    return (
      <TagsInput
        label={label}
        description={description}
        error={error}
        value={Array.isArray(value) ? value.map(String) : []}
        onChange={(next) => onChange(next.length > 0 ? next : undefined)}
      />
    );
  }

  return <JsonField {...props} />;
}

/** A shape the renderer has no widget for, edited as JSON and kept as typed until it parses. */
function JsonField(props: FieldProps) {
  const { path, value, onChange, error } = props;
  const [text, setText] = useState(value === undefined ? '' : JSON.stringify(value, null, 2));
  const [parseError, setParseError] = useState<string | null>(null);

  return (
    <Textarea
      label={fieldLabel(pathKey(path))}
      description={<FieldDescription {...props} />}
      error={parseError ?? error}
      autosize
      minRows={2}
      value={text}
      onChange={(event) => setText(event.currentTarget.value)}
      onBlur={() => {
        if (text.trim() === '') {
          setParseError(null);
          onChange(undefined);
          return;
        }
        try {
          onChange(JSON.parse(text));
          setParseError(null);
        } catch {
          setParseError('Not valid JSON');
        }
      }}
    />
  );
}

/** `home_mount`: off (null, the default) or an object with its own fields. */
function NullableObjectField({ path, value, onChange, error, children }: FieldProps & { children: ReactNode }) {
  const key = pathKey(path);
  const enabled = value !== undefined && value !== null;

  return (
    <Stack gap="sm">
      <Switch
        label={fieldLabel(key)}
        description={FIELD_COPY[key]?.description}
        error={error}
        checked={enabled}
        onChange={(event) => onChange(event.currentTarget.checked ? {} : undefined)}
      />
      {enabled && (
        <Box pl="lg" style={{ borderLeft: '2px solid var(--app-border-default)' }}>
          <Stack gap="sm">{children}</Stack>
        </Box>
      )}
    </Stack>
  );
}

const oneOfHint = (schema: JsonSchema): string | null => {
  const choices = schema.oneOf?.map((branch) => branch.required ?? []).filter((required) => required.length === 1);
  if (!choices || choices.length < 2) return null;
  return `Set exactly one of ${choices.map(([name]) => name).join(' or ')}.`;
};

/** A list of objects (`extra_mounts`, `cache_mounts`): one row per entry, one input per item key. */
function ObjectListField(props: FieldProps) {
  const { path, schema, value, onChange, error } = props;
  const label = fieldLabel(pathKey(path));
  const itemSchema = schema.items ?? {};
  const entries = Array.isArray(value) ? (value as Record<string, unknown>[]) : [];
  const hint = oneOfHint(itemSchema);
  const itemProperties = Object.entries(itemSchema.properties ?? {});

  const update = (next: Record<string, unknown>[]) => onChange(next.length > 0 ? next : undefined);
  const updateEntry = (index: number, name: string, itemValue: unknown, itemDefault: unknown) => {
    const entry = { ...entries[index] };
    if (itemValue === undefined || itemValue === '' || itemValue === itemDefault) delete entry[name];
    else entry[name] = itemValue;
    update(entries.map((current, i) => (i === index ? entry : current)));
  };

  return (
    <Input.Wrapper
      label={label}
      description={
        <>
          <FieldDescription {...props} />
          {hint && <span> {hint}</span>}
        </>
      }
      error={error}
    >
      <Stack gap="xs" mt={6}>
        {entries.map((entry, index) => (
          <Group key={index} align="flex-end" gap="xs" wrap="nowrap">
            {itemProperties.map(([name, child]) =>
              schemaTypes(child).includes('boolean') ? (
                <Checkbox
                  key={name}
                  mb={8}
                  label={humanize(name)}
                  aria-label={`${label} ${index + 1}: ${humanize(name)}`}
                  checked={(entry[name] ?? child.default) === true}
                  onChange={(event) => updateEntry(index, name, event.currentTarget.checked, child.default)}
                />
              ) : (
                <TextInput
                  key={name}
                  style={{ flex: 1 }}
                  label={humanize(name)}
                  aria-label={`${label} ${index + 1}: ${humanize(name)}`}
                  value={typeof entry[name] === 'string' ? (entry[name] as string) : ''}
                  onChange={(event) => updateEntry(index, name, event.currentTarget.value, child.default)}
                />
              ),
            )}
            <ActionIcon
              variant="subtle"
              color="gray"
              mb={4}
              aria-label={`Remove ${label} ${index + 1}`}
              onClick={() => update(entries.filter((_, i) => i !== index))}
            >
              <IconTrash size={16} />
            </ActionIcon>
          </Group>
        ))}
        <Box>
          <Button
            variant="default"
            size="xs"
            leftSection={<IconPlus size={14} />}
            onClick={() => update([...entries, {}])}
            aria-label={`Add to ${label}`}
          >
            Add
          </Button>
        </Box>
      </Stack>
    </Input.Wrapper>
  );
}

/**
 * §7.2: a writable host mount is outside the scrub guarantee, so on a manual runner each one is
 * listed in `acknowledged_writable_mounts`, by target, and a writable `home_mount` by its path.
 */
function AcknowledgementField({ path, onChange, error, config }: FieldProps & { config: RunnerConfig }) {
  const writable = writableHostMounts(config);
  const acknowledged = acknowledgedMounts(config);
  const key = pathKey(path);

  const toggle = (mount: string, checked: boolean) => {
    const next = checked ? [...new Set([...acknowledged, mount])] : acknowledged.filter((m) => m !== mount);
    onChange(next.length > 0 ? next : undefined);
  };

  return (
    <Input.Wrapper label={fieldLabel(key)} description={FIELD_COPY[key]?.description} error={error}>
      <Stack gap={6} mt={6}>
        {writable.length === 0 ? (
          <Text fz="sm" c="dimmed">
            No writable host mounts.
          </Text>
        ) : (
          writable.map((mount) => (
            <Checkbox
              key={mount}
              label={`I understand the agent can write to ${mount} on this machine`}
              checked={acknowledged.includes(mount)}
              onChange={(event) => toggle(mount, event.currentTarget.checked)}
            />
          ))
        )}
      </Stack>
    </Input.Wrapper>
  );
}

/** §6.8: the Docker socket is root on the machine, so it needs `allow_privileged_mounts`. */
function DockerSocketField(props: FieldProps & { allowed: boolean }) {
  const { path, schema, value, onChange, error, allowed } = props;
  const on = (value ?? schema.default) === true;

  return (
    <Stack gap="xs">
      <Switch
        label={fieldLabel(pathKey(path))}
        description={allowed ? <FieldDescription {...props} /> : 'Turn on Allow privileged mounts first.'}
        error={error}
        disabled={!allowed && !on}
        checked={on}
        onChange={(event) => onChange(event.currentTarget.checked)}
      />
      {on && (
        <Alert color="orange" variant="light" icon={<IconAlertTriangle size={16} />} p="xs">
          The Docker socket gives the agent root on this machine: it can start any container and read anything on the
          host.
        </Alert>
      )}
    </Stack>
  );
}
