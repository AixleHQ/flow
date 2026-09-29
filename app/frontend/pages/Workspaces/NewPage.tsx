import { Head, useForm, usePage } from '@inertiajs/react';
import { Anchor, Button, Group, NumberInput, Stack, Text, TextInput } from '@mantine/core';
import { IconArrowRight, IconCalculator, IconCheck, IconMail } from '@tabler/icons-react';

import { howItWorksPath, workspacePath } from 'shared/routes';
import { BrandLockup } from 'shared/ui';

import classes from './NewPage.module.css';

interface PageProps {
  suggestedDomain: string | null;
  suggestedName: string | null;
  defaultMaxSessions: number;
  /** Set once a confirmation link has gone out, which is the whole of that screen. */
  sentTo: string | null;
  /** Carried from the sign-in screen, where the address was typed first. */
  suggestedEmail: string | null;
  /** A stranger names the address they will own the workspace with; a signed-in person has proved theirs. */
  needsEmail: boolean;
  /** Queue-hours the workspace may spend before anyone asks it for a card. */
  freeQueueHours: number;
  /**
   * Server-side refusals. The keys arrive camelCased — the Inertia
   * prop_transformer runs over every prop, errors included — while the form's
   * own data keys are the snake_case ones the controller reads. The two do not
   * line up, so the errors are read from here rather than from form.errors.
   */
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

const domainOf = (email: string | null) => email?.split('@')[1]?.trim().toLowerCase() ?? '';

// A first guess at the workspace's name, so someone arriving from the sign-in
// screen finds the form already half-answered.
const nameFromEmail = (email: string | null) => {
  const domain = domainOf(email).split('.')[0] ?? '';
  return domain ? domain.charAt(0).toUpperCase() + domain.slice(1) : '';
};

const Pitch = () => (
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
);

const SentScreen = ({ address }: { address: string }) => (
  <section className={classes.formSide}>
    <div className={classes.form}>
      <IconMail size={32} className={classes.sentIcon} aria-hidden />
      <h2 className={classes.formTitle}>Check your email</h2>
      <Text size="sm" c="var(--app-text-secondary)">
        We sent a link to <span className={classes.domain}>{address}</span>. Opening it creates the workspace and makes
        you its administrator.
      </Text>
      <Text size="sm" c="var(--app-text-tertiary)" mt="md">
        Nothing has been created yet, and nothing will be until that link is opened. It expires in 24 hours.
      </Text>
    </div>
  </section>
);

const NewWorkspacePage = () => {
  const {
    suggestedDomain,
    suggestedName,
    defaultMaxSessions,
    sentTo,
    needsEmail,
    suggestedEmail,
    freeQueueHours,
    errors,
  } = usePage<PageProps>().props;

  const form = useForm({
    name: suggestedName ?? nameFromEmail(suggestedEmail),
    email: suggestedEmail ?? '',
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

  // The domain is never typed. It is whatever the address says it is, because a
  // workspace may only claim the domain of the person claiming it.
  const domain = needsEmail ? domainOf(form.data.email) : (suggestedDomain ?? '');

  return (
    <div className={classes.page}>
      <Head title={sentTo ? 'Check your email' : 'Create your workspace'} />
      <Pitch />

      {sentTo ? (
        <SentScreen address={sentTo} />
      ) : (
        <section className={classes.formSide}>
          <div className={classes.form}>
            <h2 className={classes.formTitle}>Create your workspace</h2>
            <Text size="sm" c="var(--app-text-secondary)" mb="lg">
              <span className={classes.domainNote}>
                {domain ? (
                  <>
                    Everyone signing in from <span className={classes.domain}>{domain}</span> joins this workspace, so
                    it is yours to claim only if it is your own.
                  </>
                ) : (
                  'Your workspace claims the domain of your work email, and everyone signing in from it joins you here.'
                )}
              </span>
            </Text>

            {errors?.base && (
              <Text size="sm" c="var(--app-danger-fg)" mb="md">
                {errors.base}
              </Text>
            )}

            <form onSubmit={submit}>
              <Stack gap="md">
                <TextInput
                  label="Workspace name"
                  placeholder="Acme Robotics"
                  required
                  size="md"
                  value={form.data.name}
                  onChange={(event) => form.setData('name', event.currentTarget.value)}
                  error={errors?.name}
                />
                {needsEmail && (
                  <TextInput
                    label="Your work email"
                    type="email"
                    placeholder="you@acme-robotics.example"
                    description="We send a link there to confirm it is yours. Nothing is created until you open it."
                    required
                    size="md"
                    value={form.data.email}
                    onChange={(event) => form.setData('email', event.currentTarget.value)}
                    error={errors?.email ?? errors?.emailDomain}
                  />
                )}
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
                  error={errors?.maxSessions}
                />
                <Button
                  type="submit"
                  loading={form.processing}
                  fullWidth
                  size="md"
                  mt="xs"
                  rightSection={<IconArrowRight size={16} />}
                >
                  {needsEmail ? 'Email me the link' : 'Create workspace'}
                </Button>
                <p className={classes.footnote}>
                  You become its first administrator and can invite the rest of the team straight away. The first{' '}
                  {freeQueueHours} queue-hours are free, and they are spent at whatever rate you run: four sessions at
                  once uses four queue-hours an hour.
                </p>
              </Stack>
            </form>
          </div>
        </section>
      )}
    </div>
  );
};

export default NewWorkspacePage;
