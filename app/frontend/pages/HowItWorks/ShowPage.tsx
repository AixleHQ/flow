import { Head, usePage } from '@inertiajs/react';
import { Anchor, Box, Button, Group, SimpleGrid, Stack, Text } from '@mantine/core';
import { IconArrowRight } from '@tabler/icons-react';

import { PublicLayout } from 'layouts/PublicLayout';

import { formatMoney, HOURS_PER_QUEUE_MONTH, monthlyCostPerQueue } from 'shared/lib/roi';
import { loginPath, newWorkspacePath, templatesPath } from 'shared/routes';
import { BrandLockup } from 'shared/ui';

import { RoiCalculator } from './components/RoiCalculator';
import classes from './ShowPage.module.css';

interface Props {
  [key: string]: unknown;
  queueHourlyRate: number;
  /** Queue-hours a new workspace may spend before anyone asks it for a card. */
  freeQueueHours: number;
  signedIn: boolean;
}

const STEPS = [
  {
    number: 'Step 01',
    title: 'Describe the process once',
    body: 'A workflow is ordered steps with the instructions, tools and repositories each one needs. Start from a template in the catalog or write your own.',
  },
  {
    number: 'Step 02',
    title: 'Agents run it in a queue',
    body: 'Every run gets its own container: the agent works, commits, opens pull requests and asks for approval where you told it to stop. A queue runs one session at a time.',
  },
  {
    number: 'Step 03',
    title: 'You pay for the queues you keep open',
    body: 'Capacity is the whole price. Two queues run two sessions side by side; raise or lower the number in settings and the bill follows within the hour.',
  },
];

const ShowPage = () => {
  const { queueHourlyRate, freeQueueHours, signedIn } = usePage<Props>().props;

  return (
    <PublicLayout>
      <Head title="How Aixle Flow works" />

      <Stack gap={64} pb={40}>
        <Box className={classes.hero}>
          <BrandLockup size="lg" />
          <h1 className={classes.heroTitle}>Hand a process to agents, pay for the queue it runs in</h1>
          <p className={classes.heroLead}>
            Flow runs your workflows the way a team would — with the same repositories, the same tools and the same
            approvals — and charges for capacity rather than for seats or for tokens.
          </p>
          <Group mt={32} gap="sm">
            <Button component="a" href={newWorkspacePath()} size="md" rightSection={<IconArrowRight size={16} />}>
              Create your workspace
            </Button>
            <Button component="a" href={templatesPath()} size="md" variant="default">
              Browse templates
            </Button>
          </Group>
        </Box>

        <Stack gap="lg">
          <div>
            <h2 className={classes.sectionTitle}>How it works</h2>
            <p className={classes.sectionLead}>Three things happen, and only the third one costs money.</p>
          </div>
          <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="lg">
            {STEPS.map((step) => (
              <div key={step.number} className={classes.step}>
                <span className={classes.stepNumber}>{step.number}</span>
                <h3 className={classes.stepTitle}>{step.title}</h3>
                <Text size="sm" c="var(--app-text-secondary)">
                  {step.body}
                </Text>
              </div>
            ))}
          </SimpleGrid>
        </Stack>

        <Stack gap="lg">
          <div>
            <h2 className={classes.sectionTitle}>What it costs</h2>
            <p className={classes.sectionLead}>
              One number, published. A queue is a reserved slot: it is charged for every hour it stands ready, whether
              or not a session is running in it.
            </p>
          </div>
          <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="lg" component="section" aria-label="What it costs">
            <div className={classes.priceCard}>
              <div className={classes.price}>
                <span className={classes.priceFigure}>{formatMoney(queueHourlyRate, 2)}</span>
                <Text c="var(--app-text-secondary)">per queue-hour</Text>
              </div>
              <Text size="sm" c="var(--app-text-secondary)" mt="sm">
                The list price of one session slot, for one hour.
              </Text>
            </div>
            <div className={classes.priceCard}>
              <div className={classes.price}>
                <span className={classes.priceFigure}>{formatMoney(monthlyCostPerQueue(queueHourlyRate))}</span>
                <Text c="var(--app-text-secondary)">per queue, per month</Text>
              </div>
              <Text size="sm" c="var(--app-text-secondary)" mt="sm">
                {HOURS_PER_QUEUE_MONTH} hours of standing capacity. No seats, no per-token bill.
              </Text>
            </div>
            <div className={classes.priceCard}>
              <div className={classes.price}>
                <span className={classes.priceFigure}>{freeQueueHours}</span>
                <Text c="var(--app-text-secondary)">queue-hours free</Text>
              </div>
              <Text size="sm" c="var(--app-text-secondary)" mt="sm">
                Every new workspace starts with them, spent at whatever rate it runs — four queues at once uses four
                queue-hours an hour. Capacity is metered hourly, so raising or lowering your limit takes effect
                immediately rather than next month.
              </Text>
            </div>
          </SimpleGrid>
        </Stack>

        <Stack gap="lg">
          <div>
            <h2 className={classes.sectionTitle}>What it is worth</h2>
            <p className={classes.sectionLead}>
              The model our team uses on a first call, with your numbers instead of theirs.
            </p>
          </div>
          <RoiCalculator queueHourlyRate={queueHourlyRate} />
          <p className={classes.footnote}>
            ROI is the saving over the period divided by what Flow costs across it. IRR is the internal rate of return
            on the cash flows — the setup in year zero, then each year&apos;s saving — which is the figure a capital
            project is normally judged by. Both are an estimate from the numbers you entered, not a quote.
          </p>
        </Stack>

        <Box className={classes.cta}>
          <h2 className={classes.sectionTitle}>Start with one workflow</h2>
          <Text c="var(--app-text-secondary)" mt="sm" maw="52ch" mx="auto">
            Claim your domain, pick how many queues to keep open, and change the number whenever the work changes.
          </Text>
          <Group justify="center" mt="xl" gap="sm">
            <Button component="a" href={newWorkspacePath()} size="md" rightSection={<IconArrowRight size={16} />}>
              Create your workspace
            </Button>
            {!signedIn && (
              <Anchor href={loginPath()} c="var(--app-text-secondary)" size="sm">
                I already have one
              </Anchor>
            )}
          </Group>
        </Box>
      </Stack>
    </PublicLayout>
  );
};

export default ShowPage;
