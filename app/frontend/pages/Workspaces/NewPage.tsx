import { Head, useForm, usePage } from '@inertiajs/react';
import { Anchor, Button, Group, NumberInput, Stack, Text, TextInput } from '@mantine/core';
import { IconArrowRight, IconCalculator, IconCheck } from '@tabler/icons-react';

import { howItWorksPath, workspacePath } from 'shared/routes';
import { BrandLockup } from 'shared/ui';

import classes from './NewPage.module.css';

interface PageProps {
  suggestedDomain: string;
  suggestedName: string | null;
  defaultMaxSessions: number;
  errors?: Record<string, string>;
  [key: string]: unknown;
}

const POINTS = [
  {
    title: 'Everyone from your domain lands here',
    body: 'Colleagues signing in with the same email domain join this workspace instead of starting their own.',
  },
  {
    title: 'A queue is one session at a time',
    body: 'Pick how many run side by side. Raise or lower it in settings whenever the work changes.',
  },
  {
    title: 'Capacity is the whole bill',
    body: 'No seats and no per-token charge — you are billed for the queues you keep open, by the hour.',
  },
];

const NewWorkspacePage = () => {
  const { suggestedDomain, suggestedName, defaultMaxSessions, errors } = usePage<PageProps>().props;

  const form = useForm({
    name: suggestedName ?? '',
    email_domain: suggestedDomain,
    max_sessions: String(defaultMaxSessions),
  });

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    // Nested under `workspace`, as every other form here posts and as the
    // controller's strong parameters expect. `wrap_parameters` is off, so a flat
    // body arrives flat and the controller reads an empty hash.
    form.transform((data) => ({ workspace: data }));
    form.post(workspacePath());
  };

  return (
    <div className={classes.page}>
      <Head title="Create your workspace" />

      <section className={classes.pitch}>
        <BrandLockup size="lg" />
        <h1 className={classes.title}>Set up your team&apos;s workspace</h1>
        <p className={classes.lead}>
          A workspace holds your projects, your workflows and the agents that run them. It takes one form and about a
          minute.
        </p>
        <ul className={classes.points}>
          {POINTS.map((point) => (
            <li key={point.title} className={classes.point}>
              <IconCheck size={18} className={classes.pointIcon} aria-hidden />
              <span>
                <b>{point.title}.</b> {point.body}
              </span>
            </li>
          ))}
        </ul>
        <Anchor href={howItWorksPath()} size="sm" fw={500}>
          <Group gap={6} wrap="nowrap" component="span">
            <IconCalculator size={16} />
            How it works, and what a queue costs
            <IconArrowRight size={14} />
          </Group>
        </Anchor>
      </section>

      <section className={classes.formSide}>
        <div className={classes.form}>
          <h2 className={classes.formTitle}>Create your workspace</h2>
          <Text size="sm" c="var(--app-text-secondary)" mb="lg">
            <span className={classes.domainNote}>
              Nobody has claimed <span className={classes.domain}>{suggestedDomain}</span> yet, so this one is yours to
              start.
            </span>
          </Text>

          <form onSubmit={submit}>
            <Stack gap="md">
              <TextInput
                label="Workspace name"
                placeholder="Acme Robotics"
                required
                size="md"
                value={form.data.name}
                onChange={(event) => form.setData('name', event.currentTarget.value)}
                error={form.errors.name || errors?.name}
              />
              <TextInput
                label="Email domain"
                description="Everyone signing in with an address here joins this workspace."
                required
                size="md"
                value={form.data.email_domain}
                onChange={(event) => form.setData('email_domain', event.currentTarget.value)}
                error={form.errors.email_domain || errors?.email_domain}
              />
              <NumberInput
                label="Concurrent sessions"
                description="How many sessions this workspace may run at once. You can change it later in settings."
                min={1}
                allowDecimal={false}
                allowNegative={false}
                required
                size="md"
                value={form.data.max_sessions}
                onChange={(value) => form.setData('max_sessions', value === '' || value == null ? '' : String(value))}
                error={form.errors.max_sessions || errors?.max_sessions}
              />
              <Button
                type="submit"
                loading={form.processing}
                fullWidth
                size="md"
                mt="xs"
                rightSection={<IconArrowRight size={16} />}
              >
                Create workspace
              </Button>
              <p className={classes.footnote}>
                You become its first administrator and can invite the rest of the team straight away.
              </p>
            </Stack>
          </form>
        </div>
      </section>
    </div>
  );
};

export default NewWorkspacePage;
