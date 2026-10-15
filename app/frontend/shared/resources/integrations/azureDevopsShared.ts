export interface AzureDevopsProject {
  id: string;
  name: string;
}

// Mirrors AzureDevops::IntegrationService::ALL_CAPABILITIES. These are Aixle's
// operation profile, not Azure's ACLs: unticking one stops the request being
// sent at all, while Azure independently decides whether the identity may
// perform the ones that are sent.
export const CAPABILITIES: { value: string; label: string; hint: string }[] = [
  {
    value: 'repositories.read',
    label: 'Clone and push repositories',
    hint: "Azure's permissions decide what may be pushed",
  },
  { value: 'pull_requests.write', label: 'Open and edit pull requests', hint: 'Never completes or merges one' },
  { value: 'pull_request_threads.write', label: 'Reply in review threads', hint: 'Comment and resolve discussions' },
  { value: 'work_items.read', label: 'Read work items', hint: 'Azure Boards tasks and comments' },
  { value: 'work_items.write', label: 'Edit work items', hint: 'Create, update and comment' },
  { value: 'builds.read', label: 'Read pipeline builds', hint: 'Build results and branch policy status' },
  {
    value: 'pull_requests.complete',
    label: 'Complete pull requests',
    hint: 'Merging. Branch policies still apply and are never bypassed',
  },
];

// Mirrors AzureDevops::IntegrationService::DEFAULT_CAPABILITIES — all of them,
// merging included. Azure's branch policies decide whether a merge is allowed;
// this list decides only which requests Aixle sends at all.
export const DEFAULT_CAPABILITIES = CAPABILITIES.map((c) => c.value);

export const capabilitiesChanged = (capabilities: string[]) =>
  capabilities.length !== DEFAULT_CAPABILITIES.length || capabilities.some((c) => !DEFAULT_CAPABILITIES.includes(c));

// The onboarding endpoints answer JSON rather than an Inertia redirect, because
// the modal keeps its state across the steps.
export const postJson = async (url: string, body: Record<string, unknown>) => {
  const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '';
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token, Accept: 'application/json' },
    body: JSON.stringify(body),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.message || 'Azure DevOps rejected the request');
  return payload;
};
