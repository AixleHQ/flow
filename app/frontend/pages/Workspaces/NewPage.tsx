import { Head, router, useForm, usePage } from '@inertiajs/react';
import { Alert, Anchor, Button, Group, Stack, Text, TextInput } from '@mantine/core';
import { IconArrowRight, IconCalculator, IconCheck, IconMail } from '@tabler/icons-react';
import { useState } from 'react';

import { type ClaimedDomain, ClaimedDomainNotice } from 'shared/components/ClaimedDomainNotice';
import { howItWorksPath, loginPath, logoutPath, marketplaceProposalPath, workspacePath } from 'shared/routes';
import { BrandLockup, PageShell } from 'shared/ui';

import classes from './NewPage.module.css';

type Refusal = string | string[];

/** How far a buyer's request to have their subscription applied has got. */
type RequestState = 'check-email' | 'pending' | 'accepted' | 'declined' | null;

interface PageProps {
  suggestedDomain: string | null;
  suggestedName: string | null;
  /** Set once a confirmation link has gone out, which is the whole of that screen. */
  sentTo: string | null;
  /** Carried from the sign-in screen, where the address was typed first. */
  suggestedEmail: string | null;
  /** A stranger names the address they will own the workspace with; a signed-in person has proved theirs. */
  needsEmail: boolean;
  /** How long the free trial lasts before anyone asks for a card. Null where AWS bills from the start. */
  trialDays: number | null;
  /** Set when the domain already has a workspace, so there is nothing here to create. */
  claimedDomain?: ClaimedDomain | null;
  /** Set while an AWS Marketplace subscription is waiting for a workspace to attach to. */
  marketplaceSubscription: boolean;
  /** How far the buyer's request to have it applied has got, if they made one. */
  subscriptionRequest: RequestState;
  /**
   * Server-side refusals. The keys arrive camelCased — the Inertia
   * prop_transformer runs over every prop, errors included — while the form's
   * own data keys are the snake_case ones the controller reads. The two do not
   * line up, so the errors are read from here rather than from form.errors.
   * A form's refusals arrive as lists of messages, the controller's own as one.
   */
  errors?: Record<string, Refusal>;
  [key: string]: unknown;
}

const POINTS = [
  {
    title: 'Everyone from your domain lands here',
    body: 'Colleagues signing in with the same email domain join this workspace instead of starting their own.',
  },
  {
    title: 'A worker runs one session at a time',
    body: 'The free trial runs one. Once you add a card, choose how many run side by side, and change it whenever the work changes.',
  },
  {
    title: 'Capacity is the whole bill',
    body: 'No seats and no per-token charge — you are billed for the workers you keep, by the hour.',
  },
];

const joined = (...refusals: (Refusal | undefined)[]) => refusals.flat().filter(Boolean).join(' ') || undefined;

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
        How it works, and what a worker costs
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

// What a buyer may do about a subscription with nowhere to go. The workspace is
// never named as a choice — it is whichever one holds their own domain — and
// the asking takes a confirmed address, so this button sends a link rather than
// raising anything.
const SubscriptionRequest = ({ claim, state, email }: { claim: ClaimedDomain; state: RequestState; email: string }) => {
  const workspace = claim.workspaceName ?? 'the workspace at your domain';

  if (state === 'check-email')
    return (
      <Text size="sm" c="var(--app-text-secondary)" mt="md">
        We sent a link to <b>{email}</b>. Opening it confirms the address is yours and puts the request to the
        administrators of {workspace}. Nobody has been asked anything yet.
      </Text>
    );

  if (state === 'pending')
    return (
      <Text size="sm" c="var(--app-text-secondary)" mt="md">
        The administrators of {workspace} have been asked to apply your subscription. They decide whether it is applied,
        and we will email you either way. Nothing is billed through AWS until one of them accepts.
      </Text>
    );

  const declined = state === 'declined';

  return (
    <>
      <Text size="sm" c="var(--app-text-secondary)" mt="md">
        {declined ? (
          <>
            An administrator of {workspace} did not accept the request. Your subscription is unchanged and is attached
            to nothing. Speak to someone there before asking again, or unsubscribe in AWS Marketplace if you no longer
            want it.
          </>
        ) : (
          <>
            Your AWS Marketplace subscription is recorded and is not attached to a workspace yet. Nothing has been lost
            and you are not paying twice. You can ask the administrators of {workspace} to apply it — they decide, and
            until one of them accepts nothing about that workspace changes.
          </>
        )}
      </Text>
      {/* Offered after a refusal too. A declined request is answered, not
          final: the buyer has paid, the subscription is still attached to
          nothing, and telling them to ask again while giving them nothing to
          ask with leaves them stuck for good. */}
      <Button
        fullWidth
        size="md"
        mt="md"
        variant={declined ? 'default' : 'filled'}
        onClick={() => router.post(marketplaceProposalPath(), { email })}
        disabled={!email}
      >
        {declined ? 'Ask again' : 'Ask them to apply it'}
      </Button>
    </>
  );
};

/** What a buyer arriving from AWS wants done with the subscription. */
type BuyerMode = 'create' | 'attach';

// The subscription has to go somewhere, and the page used to assume a new
// workspace: a buyer whose team already has one found that out only after
// typing an address at its domain. The workspace is still never chosen here --
// it is whichever one uses the address's domain -- so this asks for nothing
// but the address, and sends a link rather than raising anything.
const AttachForm = ({ initialEmail, refusal }: { initialEmail: string; refusal?: string }) => {
  const [email, setEmail] = useState(initialEmail);
  const [sending, setSending] = useState(false);

  return (
    <Stack gap="md">
      <TextInput
        label="Your work email at that workspace"
        type="email"
        placeholder="you@acme-robotics.example"
        description="We send a link there to confirm it is yours. The workspace is whichever one uses that domain, and nothing about it changes until an administrator there accepts."
        required
        size="md"
        value={email}
        onChange={(event) => setEmail(event.currentTarget.value)}
        error={refusal}
      />
      <Button
        fullWidth
        size="md"
        mt="xs"
        loading={sending}
        disabled={!email}
        rightSection={<IconArrowRight size={16} />}
        onClick={() => {
          setSending(true);
          router.post(marketplaceProposalPath(), { email }, { onFinish: () => setSending(false) });
        }}
      >
        Email me the link
      </Button>
    </Stack>
  );
};

const Chooser = ({ choose }: { choose: (mode: BuyerMode) => void }) => (
  <Stack gap="md">
    <Text size="sm" c="var(--app-text-secondary)">
      Your AWS Marketplace subscription is recorded. Where should it go?
    </Text>
    <Button size="md" fullWidth onClick={() => choose('create')}>
      Create a new workspace
    </Button>
    <Button size="md" fullWidth variant="default" onClick={() => choose('attach')}>
      Apply it to a workspace that already exists
    </Button>
  </Stack>
);

// Reached two ways. Someone signed in gets here from their own proved address,
// and signing out is their way to the sign-in screen where the methods named
// here are offered. A Marketplace buyer was signed out on arrival, so there is
// nothing to sign out of and the sign-in screen is a link away — and their
// subscription has nowhere to attach, which is the part they came to find out.
const ClaimedScreen = ({
  claim,
  signedIn,
  subscriptionHeld,
  requestState,
  refusal,
  email,
}: {
  claim: ClaimedDomain;
  signedIn: boolean;
  subscriptionHeld: boolean;
  requestState: RequestState;
  /** Why the last thing they tried was refused. Drawn here because this screen replaces the form that would have drawn it. */
  refusal?: string;
  email: string;
}) => {
  // "Already has a workspace" is the answer to somebody who tried to create
  // one. A buyer who asked for the subscription to be applied to it is not
  // being told no, so while the ask is under way the heading says where it is.
  const asking = subscriptionHeld && (requestState === 'check-email' || requestState === 'pending');
  const title = !asking
    ? 'Your domain already has a workspace'
    : requestState === 'check-email'
      ? 'Check your email'
      : 'Your request is with the administrators';

  return (
    <PageShell variant="centered">
      <Head title={title} />
      <div className={classes.form}>
        <Group mb="xl">
          <BrandLockup />
        </Group>
        <h2 className={classes.formTitle}>{title}</h2>
        {!asking && (
          <Text size="sm" c="var(--app-text-secondary)" mb="md">
            Each domain has one workspace, so there is no second one to create for yours.
          </Text>
        )}
        <ClaimedDomainNotice claim={claim} inviteOffered={!subscriptionHeld} />
        {refusal && (
          <Alert color="red" mt="md" variant="light">
            {refusal}
          </Alert>
        )}
        {subscriptionHeld && <SubscriptionRequest claim={claim} state={requestState} email={email} />}
        {signedIn ? (
          <Button fullWidth size="md" mt="lg" variant="default" onClick={() => router.delete(logoutPath())}>
            {claim.joinMethods.length > 0 ? 'Sign out to sign in another way' : 'Sign out'}
          </Button>
        ) : (
          claim.joinMethods.length > 0 && (
            <Button fullWidth size="md" mt="lg" variant="default" onClick={() => router.visit(loginPath())}>
              Go to sign in
            </Button>
          )
        )}
      </div>
    </PageShell>
  );
};

const NewWorkspacePage = () => {
  const {
    suggestedDomain,
    suggestedName,
    sentTo,
    needsEmail,
    suggestedEmail,
    trialDays,
    claimedDomain,
    marketplaceSubscription,
    subscriptionRequest,
    errors = {},
  } = usePage<PageProps>().props;

  // A buyer is signed out on arrival; somebody signed in is making a workspace
  // of their own and gets the form straight away. A refusal of an ask comes
  // back on the ask, not on the form it never used.
  const buyer = marketplaceSubscription && needsEmail;
  const [mode, setMode] = useState<BuyerMode | null>(() => {
    if (!buyer) return 'create';
    return errors.base && suggestedEmail ? 'attach' : null;
  });

  const form = useForm({
    name: suggestedName ?? nameFromEmail(suggestedEmail),
    email: suggestedEmail ?? '',
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

  // A refusal for a field this page does not draw — the address of someone
  // signed in — would otherwise vanish, and the form would just sit there.
  const drawnFields = needsEmail ? ['name', 'email', 'emailDomain'] : ['name'];
  const undrawn = Object.entries(errors)
    .filter(([key]) => !drawnFields.includes(key))
    .flatMap(([, refusal]) => refusal);

  if (claimedDomain)
    return (
      <ClaimedScreen
        claim={claimedDomain}
        signedIn={!needsEmail}
        subscriptionHeld={marketplaceSubscription}
        requestState={subscriptionRequest}
        refusal={undrawn.join(' ') || undefined}
        email={form.data.email || (suggestedEmail ?? '')}
      />
    );

  const title = buyer && mode !== 'create' ? 'Set up your subscription' : 'Create your workspace';

  if (!sentTo && buyer && mode !== 'create')
    return (
      <div className={classes.page}>
        <Head title={title} />
        <Pitch />
        <section className={classes.formSide}>
          <div className={classes.form}>
            <h2 className={classes.formTitle}>{title}</h2>
            {mode === 'attach' ? (
              <>
                <AttachForm initialEmail={suggestedEmail ?? ''} refusal={joined(errors.base)} />
                <Text size="sm" c="var(--app-text-tertiary)" mt="md">
                  No workspace yet?{' '}
                  <Anchor size="sm" component="button" type="button" onClick={() => setMode('create')}>
                    Create a new one instead
                  </Anchor>
                </Text>
              </>
            ) : (
              <Chooser choose={setMode} />
            )}
          </div>
        </section>
      </div>
    );

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
            {buyer && (
              <Text size="sm" c="var(--app-text-tertiary)" mb="sm">
                Already have a workspace?{' '}
                <Anchor size="sm" component="button" type="button" onClick={() => setMode('attach')}>
                  Apply the subscription to it instead
                </Anchor>
              </Text>
            )}
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

            {undrawn.map((message) => (
              <Text key={message} size="sm" c="var(--app-danger-fg)" mb="md">
                {message}
              </Text>
            ))}

            <form onSubmit={submit}>
              <Stack gap="md">
                <TextInput
                  label="Workspace name"
                  placeholder="Acme Robotics"
                  required
                  size="md"
                  value={form.data.name}
                  onChange={(event) => form.setData('name', event.currentTarget.value)}
                  error={joined(errors.name)}
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
                    error={joined(errors.email, errors.emailDomain)}
                  />
                )}
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
                  You become its first administrator and can invite the rest of the team straight away.
                  {trialDays !== null && (
                    <> The first {trialDays} days are free, on one worker; add a card to keep going after that.</>
                  )}
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
