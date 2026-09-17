export interface ToolGroup {
  tag: string;
  label: string;
  toolIds: number[];
}

export interface ToolOption {
  id: number;
  name: string;
}

/** One collapsible block of the picker: a tag group, or the ungrouped leftovers. */
export interface ToolPickerSection {
  /** `grp:<tag>` for a tag group, `ungrouped` for the trailing bucket. */
  key: string;
  label: string;
  /** True only for the bucket of tools that carry no UI-visible tag. */
  ungrouped: boolean;
  tools: ToolOption[];
}

/** How much of a section the current selection covers. */
export type SectionState = 'none' | 'partial' | 'all';

/** A chip in the picker's input: a whole group, or one individual tool. */
export interface ToolPickerPill {
  key: string;
  label: string;
  /** Ids this chip stands for — removing it drops exactly these. */
  toolIds: number[];
}

export const UNGROUPED_KEY = 'ungrouped';
export const UNGROUPED_LABEL = 'Ungrouped';

const GROUP_PREFIX = 'grp:';

const asArray = <T>(value: T[] | null | undefined): T[] => (Array.isArray(value) ? value : []);

/**
 * A tag group ("Board management", "Slack") is a section of the picker, not an
 * atom: the whole group can be attached in one click from its header, and any
 * subset of its tools can be attached individually. The selection is therefore
 * always a plain list of tool ids — there is no group token to expand, and a
 * partially selected group survives a round trip untouched.
 *
 * Shared by all three tool pickers (workflow base resources, step session
 * editor, new session) so a group behaves identically wherever it is offered.
 */
export function toolPickerSections(tools: ToolOption[], groups: ToolGroup[] = []): ToolPickerSection[] {
  const byId = new Map(
    asArray(tools)
      .filter((t) => t?.id != null)
      .map((t) => [t.id, { id: t.id, name: t.name ?? '' }]),
  );

  const sections = asArray(groups)
    .map((group) => ({
      key: `${GROUP_PREFIX}${group.tag}`,
      label: group.label,
      ungrouped: false,
      tools: asArray(group.toolIds).flatMap((id) => {
        const tool = byId.get(id);
        return tool ? [tool] : [];
      }),
    }))
    .filter((section) => section.tools.length > 0);

  const grouped = new Set(sections.flatMap((s) => s.tools.map((t) => t.id)));
  const rest = [...byId.values()].filter((t) => !grouped.has(t.id));

  return rest.length > 0
    ? [...sections, { key: UNGROUPED_KEY, label: UNGROUPED_LABEL, ungrouped: true, tools: rest }]
    : sections;
}

export function sectionState(section: ToolPickerSection, selectedIds: number[]): SectionState {
  const selected = new Set(asArray(selectedIds));
  const hits = section.tools.filter((t) => selected.has(t.id)).length;

  if (hits === 0) return 'none';
  return hits === section.tools.length ? 'all' : 'partial';
}

/** Header click: a fully selected section clears, anything else fills. */
export function toggleSection(section: ToolPickerSection, selectedIds: number[]): number[] {
  const ids = asArray(selectedIds);
  const memberIds = section.tools.map((t) => t.id);

  if (sectionState(section, ids) === 'all') {
    const members = new Set(memberIds);
    return ids.filter((id) => !members.has(id));
  }

  const selected = new Set(ids);
  return [...ids, ...memberIds.filter((id) => !selected.has(id))];
}

export function toggleTool(toolId: number, selectedIds: number[]): number[] {
  const ids = asArray(selectedIds);

  return ids.includes(toolId) ? ids.filter((id) => id !== toolId) : [...ids, toolId];
}

/**
 * Chips for the input. A group that is selected whole collapses into a single
 * chip — otherwise attaching "Board management" would spray six chips across a
 * 460px drawer. A partially selected group shows its members one by one, which
 * is the only honest way to render a subset.
 *
 * Ids that match no known tool (a stale selection, a tool that lost visibility)
 * get no chip but are never dropped from the value — see `toolPickerPills`'s
 * callers, which only ever remove the ids a chip names.
 */
export function toolPickerPills(sections: ToolPickerSection[], selectedIds: number[]): ToolPickerPill[] {
  const selected = new Set(asArray(selectedIds));

  return asArray(sections).flatMap((section) => {
    if (!section.ungrouped && sectionState(section, selectedIds) === 'all') {
      return [{ key: section.key, label: section.label, toolIds: section.tools.map((t) => t.id) }];
    }

    return section.tools
      .filter((t) => selected.has(t.id))
      .map((t) => ({ key: `tool:${t.id}`, label: t.name, toolIds: [t.id] }));
  });
}

/**
 * Search narrows to matching tools, but a group whose own label matches keeps
 * all of its members — typing "slack" should offer the whole Slack family, not
 * only the tools with "slack" in their name.
 */
export function filterSections(sections: ToolPickerSection[], query: string): ToolPickerSection[] {
  const needle = query.trim().toLowerCase();
  if (needle === '') return asArray(sections);

  return asArray(sections).flatMap((section) => {
    if (!section.ungrouped && section.label.toLowerCase().includes(needle)) return [section];

    const tools = section.tools.filter((t) => t.name.toLowerCase().includes(needle));
    return tools.length > 0 ? [{ ...section, tools }] : [];
  });
}
