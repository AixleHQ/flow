export interface Trigger {
  id: number;
  kind: string;
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
  // Who added the trigger. Off-board kinds run as this user and use their
  // credentials; null on rows created before the creator was recorded (or whose
  // account was deleted), and those are skipped instead of firing unattended.
  created_by?: { id: number; name: string } | null;
}
