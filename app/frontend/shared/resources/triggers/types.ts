// A trigger as the triggers API serializes it (WorkflowTriggers::Serializer).
// snake_case: it arrives over the JSON API, not as Inertia props.
export interface Trigger {
  id: number;
  kind: string;
  // What starts the run: board, chat, schedule, webhook, tracker or event.
  source?: string;
  // The messenger a chat trigger listens to, e.g. slack.
  chat_provider?: string | null;
  event_type: string;
  name?: string | null;
  trigger_mode?: string;
  cooldown_seconds?: number;
  notify_on_failure?: boolean;
  enabled?: boolean;
  column_name?: string;
  board_column_id?: number;
  subject_policy?: string;
  subject_column_id?: number | null;
  subject_title_template?: string | null;
  filter_predicate?: Record<string, unknown>;
  schedule_config?: { cron?: string; timezone?: string };
  // Tracker triggers: the tracker listened to (null = any), and what a change
  // Aixle itself made does.
  project_tracker_id?: number | null;
  aixle_changes?: string;
  verification_strategy?: string | null;
  webhook_url?: string | null;
  workflow_id?: number | null;
  workflow_name?: string | null;
  // Who added the trigger. Off-board kinds run as this user and use their
  // credentials; null on rows created before the creator was recorded (or whose
  // account was deleted), and those are skipped instead of firing unattended.
  created_by?: { id: number; name: string } | null;
}

export interface TriggerColumnOption {
  id: number;
  name: string;
  boundWorkflowName?: string | null;
}

export interface TriggerWorkflowOption {
  id: number;
  name: string;
}
