export interface ToolGroup {
  tag: string;
  label: string;
  toolIds: number[];
}

export interface ToolOption {
  id: number;
  name: string;
}

const GROUP_PREFIX = 'grp:';

const groupValue = (group: ToolGroup) => `${GROUP_PREFIX}${group.tag}`;

const memberIds = (groups: ToolGroup[]) =>
  new Set((Array.isArray(groups) ? groups : []).flatMap((g) => g.toolIds ?? []));

/**
 * A tag group ("Board management", "Slack") is offered as ONE picker entry that
 * attaches every tool carrying the tag — members are never listed one by one.
 * The picker's value is therefore not the raw id list: grouped ids collapse
 * into their group token, and only ungrouped tools stand on their own.
 *
 * Shared by all three tool pickers (workflow base resources, step session
 * editor, new session) so a group behaves identically wherever it is offered.
 */
export function toolPickerData(tools: ToolOption[], groups: ToolGroup[] = []) {
  const members = memberIds(groups);

  return [
    ...(Array.isArray(groups) ? groups : []).map((g) => ({ value: groupValue(g), label: g.label })),
    ...(Array.isArray(tools) ? tools : [])
      .filter((t) => t?.id != null && !members.has(t.id))
      .map((t) => ({ value: String(t.id), label: t.name ?? '' })),
  ];
}

/** Tool ids → picker values (group tokens + ungrouped ids). */
export function toolPickerValue(ids: number[], groups: ToolGroup[] = []): string[] {
  const selected = new Set(Array.isArray(ids) ? ids : []);
  const members = memberIds(groups);

  return [
    ...(Array.isArray(groups) ? groups : [])
      .filter((g) => (g.toolIds ?? []).some((id) => selected.has(id)))
      .map(groupValue),
    ...[...selected].filter((id) => !members.has(id)).map(String),
  ];
}

/** Picker values → tool ids, expanding every group token into its members. */
export function toolIdsFromPickerValue(values: string[], groups: ToolGroup[] = []): number[] {
  const ids = new Set<number>();

  (Array.isArray(values) ? values : []).forEach((v) => {
    if (v.startsWith(GROUP_PREFIX)) {
      (Array.isArray(groups) ? groups : []).find((g) => groupValue(g) === v)?.toolIds?.forEach((id) => ids.add(id));
    } else {
      ids.add(Number(v));
    }
  });

  return [...ids];
}
