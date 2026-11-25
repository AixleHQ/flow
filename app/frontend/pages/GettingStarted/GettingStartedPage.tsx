import { Head, Link, router, usePage } from '@inertiajs/react';
import { Anchor, Badge, Button, Card, Group, SimpleGrid, Stack, Text, ThemeIcon } from '@mantine/core';
import { IconPlugConnected, IconRoute, IconTemplate, IconWand } from '@tabler/icons-react';
import { useId, type ReactNode } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import { useCanWrite } from 'shared/lib/hooks/useCanWrite';
import { useProductTour } from 'shared/lib/productTour';
import { companyGettingStartedBuildWithAiPath, mcpProfilePath, profilePath, templatesPath } from 'shared/routes';
import { PageHeader } from 'shared/ui/PageHeader';
import type { SharedProps } from 'shared/ui/types';

import classes from './GettingStartedPage.module.css';

interface GettingStartedPageProps extends SharedProps {
  helloFlowAvailable: boolean;
  helloFlowPath: string;
  hasProjects: boolean;
}

interface StepCardProps {
  icon: ReactNode;
  title: string;
  description: string;
  status?: ReactNode;
  children: ReactNode;
}

function StepCard({ icon, title, description, status, children }: StepCardProps) {
  const titleId = useId();

  return (
    <Card component="section" aria-labelledby={titleId} withBorder padding="lg" radius="md" className={classes.card}>
      <Stack gap="sm" h="100%">
        <Group justify="space-between" wrap="nowrap">
          <Group gap="sm" wrap="nowrap">
            <ThemeIcon variant="light" size="lg" radius="md">
              {icon}
            </ThemeIcon>
            <Text component="h2" id={titleId} fw={600} size="md">
              {title}
            </Text>
          </Group>
          {status}
        </Group>
        <Text size="sm" c="var(--app-text-secondary)" className={classes.description}>
          {description}
        </Text>
        <Group gap="sm">{children}</Group>
      </Stack>
    </Card>
  );
}

export default function GettingStartedPage() {
  const { currentUser, helloFlowAvailable } = usePage<GettingStartedPageProps>().props;
  const canWrite = useCanWrite();
  const { start } = useProductTour();
  const agentConnected = (currentUser?.configuredAgents.length ?? 0) > 0;

  const tourCard = (
    <StepCard
      icon={<IconRoute size={18} />}
      title="Take the product tour"
      description="See how Flow works and run your first workflow in about 5 minutes."
    >
      {canWrite ? (
        <Stack gap={4}>
          <Button onClick={() => start('a')} disabled={!agentConnected}>
            Take the product tour
          </Button>
          {!agentConnected && (
            <Text size="xs" c="var(--app-text-tertiary)">
              Connect an agent first
            </Text>
          )}
        </Stack>
      ) : (
        <Button onClick={() => start('b')}>Take the product tour</Button>
      )}
    </StepCard>
  );

  return (
    <AuthLayout>
      <Head title="Getting started" />
      <PageHeader title="Getting started" subtitle="Everything you need to run your first workflow in Flow" mb={24} />

      {canWrite ? (
        <SimpleGrid cols={{ base: 1, md: 2 }} spacing="md">
          <StepCard
            icon={<IconPlugConnected size={18} />}
            title="Connect your agents"
            description="Flow runs workflows with your AI agent (Claude Code, Codex…). Connect one to start."
            status={
              agentConnected && (
                <Badge color="green" variant="light">
                  Connected ✓
                </Badge>
              )
            }
          >
            <Button component={Link} href={profilePath()} variant={agentConnected ? 'default' : 'filled'}>
              {agentConnected ? 'Manage agents' : 'Connect an agent'}
            </Button>
          </StepCard>

          {helloFlowAvailable && tourCard}

          <StepCard
            icon={<IconTemplate size={18} />}
            title="Discover community templates"
            description="Ready-made workflows shared by the community. Install one in a click."
          >
            <Button component={Link} href={templatesPath()} variant="default">
              Browse templates
            </Button>
          </StepCard>

          <StepCard
            icon={<IconWand size={18} />}
            title="Build your own"
            description="Describe your process and let AI draft the workflow, or connect Flow to your own AI client (Claude, Cursor) via Personal MCP."
          >
            <Button variant="default" onClick={() => router.post(companyGettingStartedBuildWithAiPath())}>
              Build with AI
            </Button>
            <Anchor component={Link} href={mcpProfilePath()} size="sm">
              Set up Personal MCP
            </Anchor>
          </StepCard>
        </SimpleGrid>
      ) : (
        <SimpleGrid cols={{ base: 1, md: 2 }} spacing="md">
          {tourCard}
        </SimpleGrid>
      )}
    </AuthLayout>
  );
}
