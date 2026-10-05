import { Head, usePage } from '@inertiajs/react';

import type { Integration, Project } from '@/types/generated';

import type { AzureDevopsProps } from 'shared/resources/integrations/AzureDevopsConnectModal';
import type { GithubProps } from 'shared/resources/integrations/GithubConnectModal';
import {
  IntegrationsContent,
  type SlackProps,
  type TeamsProps,
} from 'shared/resources/integrations/IntegrationsContent';
import type { JiraProps } from 'shared/resources/integrations/JiraConnectModal';
import type { LinearProps } from 'shared/resources/integrations/LinearConnectModal';
import type { YoutrackProps } from 'shared/resources/integrations/YoutrackConnectModal';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Props {
  project: Project;
  integrations: Integration[];
  azureDevops?: AzureDevopsProps;
  github?: GithubProps;
  jira?: JiraProps;
  linear?: LinearProps;
  youtrack?: YoutrackProps;
  slack?: SlackProps;
  teams?: TeamsProps;
}

const IntegrationsPage = () => {
  const { project, integrations, azureDevops, github, jira, linear, youtrack, slack, teams } = usePage<{ props: Props }>()
    .props as unknown as Props;

  return (
    <>
      <Head title={`Integrations — ${project.name}`} />
      <IntegrationsContent
        integrations={integrations}
        basePath={`/company/projects/${project.id}/integrations`}
        title="Integrations"
        azureDevops={azureDevops}
        github={github}
        jira={jira}
        linear={linear}
        youtrack={youtrack}
        slack={slack}
        teams={teams}
      />
    </>
  );
};

setPageLayout(IntegrationsPage, persistentProjectLayout);

export default IntegrationsPage;
