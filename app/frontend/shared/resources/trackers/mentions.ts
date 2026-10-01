const REASONS: Record<string, string> = {
  azure_devops:
    'Aixle learns its own Azure DevOps account from the first work item the connection creates, updates, moves or assigns. Until then it cannot recognise a mention.',
  jira: 'This Jira connection acts as a person, so Aixle cannot recognise a mention of it. Tick “This Atlassian account is kept for Aixle” on the Integrations page if the account is kept for Aixle, or connect a service account.',
};

// Why a comment mentioning Aixle cannot start anything in this tracker yet; null when it can.
export function mentionBlocker(tracker: { provider: string; mentionsRecognized?: boolean }): string | null {
  if (tracker.mentionsRecognized !== false) return null;
  return (
    REASONS[tracker.provider] ??
    'Aixle does not know its own account in this tracker yet, so it cannot recognise a mention.'
  );
}
