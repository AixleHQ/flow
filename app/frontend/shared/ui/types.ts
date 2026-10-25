import type { CurrentUser, Project } from '@/types/generated';

export type AgentType = 'codex' | 'cursor_cli' | 'gemini_cli' | 'antigravity_cli' | 'claude_code' | 'grok' | 'kiro_cli';
export type UserRole = 'employee' | 'admin' | 'super_admin' | 'viewer';

// Both lists are kept here by hand (agentRuntimes.ts and the role labels are keyed by them), while
// the server's own lists — CompanyMembership::AVAILABLE_AGENTS and the membership roles — reach the
// generated types. These stop tsc the moment the two differ, e.g. a runtime added on the server only.
type SameUnion<A, B> = [A] extends [B] ? ([B] extends [A] ? true : false) : false;
type Expect<T extends true> = T;
export type AgentTypeMatchesServer = Expect<SameUnion<AgentType, NonNullable<CurrentUser['defaultAgentRuntime']>>>;
export type UserRoleMatchesServer = Expect<SameUnion<UserRole, NonNullable<CurrentUser['currentRole']>>>;

// The flags declared `client: true` in config/feature_flags.yml, camelized as the `features` shared
// prop names them, so a misspelled flag fails tsc. Kept here by hand, like the two lists above
// (Typelizer writes no file for a resource without attributes, which is what an empty registry
// gives); test/config/feature_flag_name_test.rb fails the moment this list and the registry differ.
// One quoted name per member (`'boardAiSummary' | 'newSidebar'`), and `never` while there is none.
// When this list gains its first member, prefer replacing it: an Alba resource declaring the
// `client: true` flags as `typelize :boolean` attributes makes Typelizer generate a `Features`
// interface, and `useFeatureFlag(name: keyof Features)` then needs no hand-written list and no drift
// test, because one class produces both the payload and the type. That is only possible once a flag
// exists: Typelizer 0.14 drops an attribute-less resource before writing any file.
export type FeatureFlagName = never;

export interface ProjectPermissions {
  canExecute: boolean;
  canManage: boolean;
  canManageCompany?: boolean;
}

export type SharedProject = Pick<Project, 'id' | 'name' | 'slug' | 'state' | 'favorite'>;

export interface SharedSettings {
  env: string;
  domain: string;
  githubAppSlug: string | null;
  appVersion: string | null;
  sentryFrontendDsn: string | null;
  sentryTracesSampleRate?: number;
  /** Optional: a page served by an older pod does not send it. */
  selfServeSignup?: boolean;
}

export interface SharedPermissions {
  isAdmin: boolean;
  canManageMembers: boolean;
  canManageProjects: boolean;
  /** False for a viewer. Optional: a page served by an older pod does not send it. */
  canWrite?: boolean;
  /** An admin, where we host. Optional: a page served by an older pod does not send it. */
  canManageBilling?: boolean;
}

/**
 * Where a workspace's billing stands. A blocked one carries why, which decides what
 * undoes it: a card for a spent allowance or an ended subscription, the open invoice
 * for a failed payment.
 */
export type BillingStatus = 'trialing' | 'active' | 'cancelling' | 'allowance' | 'canceled' | 'payment_failed';

/** Sent only while a workspace is on free capacity, or has spent it. */
export interface SharedTrial {
  state: 'trialing' | 'blocked';
  /** Optional: a page served by an older pod does not send it. */
  status?: BillingStatus;
  allowanceHours: number;
  usedHours: number;
  remainingHours: number;
  /** The workspace's own limit, or null when it has set none. */
  maxSessions: number | null;
  /** What is left, in wall-clock hours at that limit. Null without one. */
  hoursLeftAtCurrentRate: number | null;
  /** False where this installation has no payment provider configured. */
  canPay: boolean;
}

export interface SharedProps {
  currentUser: CurrentUser | null;
  // Most flash entries are strings (notice/alert). `needs_setup` is a list of
  // "what was not copied / needs setup" messages surfaced after a catalog copy.
  flash: Record<string, string | string[] | undefined>;
  projects?: SharedProject[];
  permissions?: SharedPermissions;
  settings: SharedSettings;
  trial?: SharedTrial | null;
  /** Server-resolved `client: true` flags; read them with useFeatureFlag. Optional: a page served by an older pod does not send it. */
  features?: Partial<Record<FeatureFlagName, boolean>>;
  [key: string]: unknown;
}
