const REASONS: Record<string, string> = {
  azure_devops:
    'Aixle reads its own Azure DevOps account when the connection is made or tested. Use Test connection on the Integrations page; until then it cannot recognise a mention.',
  github:
    'This deployment has no GitHub App slug configured, so Aixle does not know the name it is mentioned by and cannot recognise a mention.',
  jira: 'This Jira connection acts as a person, so Aixle cannot recognise a mention of it. Tick “This Atlassian account is kept for Aixle” on the Integrations page if the account is kept for Aixle, or connect a service account.',
  linear:
    'This Linear connection acts as the person whose API key it uses, so Aixle cannot recognise a mention of it. Tick “This Linear account is kept for Aixle” on the Integrations page if the account is kept for Aixle, or install Aixle’s Linear app.',
};

// Why a comment mentioning Aixle cannot start anything in this tracker yet; null when it can.
export function mentionBlocker(tracker: { provider: string; mentionsRecognized?: boolean }): string | null {
  if (tracker.mentionsRecognized !== false) return null;
  return (
    REASONS[tracker.provider] ??
    'Aixle does not know its own account in this tracker yet, so it cannot recognise a mention.'
  );
}
