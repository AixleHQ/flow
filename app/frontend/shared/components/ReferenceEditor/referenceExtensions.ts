import {
  autocompletion,
  type Completion,
  type CompletionContext,
  type CompletionResult,
  completionKeymap,
} from '@codemirror/autocomplete';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { EditorState, type Extension, RangeSetBuilder, StateEffect, StateField } from '@codemirror/state';
import {
  Decoration,
  type DecorationSet,
  EditorView,
  hoverTooltip,
  keymap,
  type Tooltip,
  WidgetType,
} from '@codemirror/view';

import { brokenReferenceLabel, type ParsedReference, type ReferenceKind, scanReferences } from 'shared/lib/references';

import { referenceIcon } from './icons';

export interface ReferenceItem {
  /** What the editor stores, e.g. `{{asset:12}}`. */
  token: string;
  kind: ReferenceKind;
  label: string;
  hint: string;
  /** Menu section, e.g. "Assets". */
  group: string;
  /** Shown instead of the hint; the row cannot be inserted. */
  disabledReason?: string;
}

export interface ReferenceCatalog {
  items: readonly ReferenceItem[];
  groups: readonly string[];
  /** Pills of tokens the catalog does not know yet stay neutral instead of broken. */
  loading: boolean;
  editable: boolean;
}

const EMPTY_CATALOG: ReferenceCatalog = { items: [], groups: [], loading: false, editable: true };

export const setReferenceCatalog = StateEffect.define<ReferenceCatalog>();

interface IndexedCatalog extends ReferenceCatalog {
  byToken: ReadonlyMap<string, ReferenceItem>;
}

const index = (catalog: ReferenceCatalog): IndexedCatalog => ({
  ...catalog,
  byToken: new Map(catalog.items.map((item) => [item.token, item])),
});

const catalogField = StateField.define<IndexedCatalog>({
  create: () => index(EMPTY_CATALOG),
  update(value, tr) {
    for (const effect of tr.effects) if (effect.is(setReferenceCatalog)) return index(effect.value);
    return value;
  },
});

interface ReferenceCompletion extends Completion {
  disabled?: boolean;
}

const KIND_NAMES: Record<ReferenceKind, string> = {
  asset: 'Asset',
  output: 'Output',
  step: 'Session',
  mcp: 'MCP server',
  skill: 'Skill',
  tool: 'Tool',
  config_item: 'Config item',
};

type PillState = 'ok' | 'broken' | 'loading';

interface Pill {
  ref: ParsedReference;
  state: PillState;
  label: string;
  item?: ReferenceItem;
}

function pendingLabel(ref: ParsedReference): string {
  if (ref.kind === 'output' && ref.name) return ref.name;
  if (ref.kind === 'step') return 'Session';
  return `${KIND_NAMES[ref.kind]} #${ref.id ?? '?'}`;
}

function pillFor(ref: ParsedReference, catalog: IndexedCatalog): Pill {
  const item = catalog.byToken.get(ref.token);
  if (item) return { ref, state: 'ok', label: item.label, item };
  if (catalog.loading && ref.valid) return { ref, state: 'loading', label: pendingLabel(ref) };
  return { ref, state: 'broken', label: brokenReferenceLabel(ref) };
}

class PillWidget extends WidgetType {
  constructor(
    readonly kind: ReferenceKind,
    readonly label: string,
    readonly state: PillState,
  ) {
    super();
  }

  eq(other: PillWidget) {
    return other.kind === this.kind && other.label === this.label && other.state === this.state;
  }

  toDOM() {
    const pill = document.createElement('span');
    pill.className = `cm-ref-pill cm-ref-pill-${this.state}`;
    pill.dataset.kind = this.kind;
    pill.dataset.state = this.state;
    pill.appendChild(referenceIcon(this.state === 'ok' ? this.kind : this.state));
    const label = document.createElement('span');
    label.textContent = this.label;
    pill.appendChild(label);
    return pill;
  }
}

function buildPills(text: string, catalog: IndexedCatalog): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  for (const ref of scanReferences(text)) {
    const pill = pillFor(ref, catalog);
    builder.add(ref.from, ref.to, Decoration.replace({ widget: new PillWidget(ref.kind, pill.label, pill.state) }));
  }
  return builder.finish();
}

const pillsField = StateField.define<DecorationSet>({
  create: (state) => buildPills(state.doc.toString(), state.field(catalogField)),
  update(pills, tr) {
    if (tr.docChanged || tr.effects.some((effect) => effect.is(setReferenceCatalog))) {
      return buildPills(tr.state.doc.toString(), tr.state.field(catalogField));
    }
    return pills;
  },
  provide: (field) => [
    EditorView.decorations.from(field),
    // A token is one unit: the caret steps over it and Backspace/Delete remove it whole.
    EditorView.atomicRanges.of((view) => view.state.field(field)),
  ],
});

// `@` opens the picker at the start of a line or after whitespace, `(` or `[` — never inside a
// word, so an e-mail address stays text. The query is what follows, up to the first space.
const TRIGGER = /(?:^|[\s([])@([^\s@]{0,40})$/;

function matchRange(label: string, query: string): readonly number[] {
  if (!query) return [];
  const at = label.toLowerCase().indexOf(query);
  return at < 0 ? [] : [at, at + query.length];
}

function referenceSource(onInsert: (item: ReferenceItem) => void) {
  return (context: CompletionContext): CompletionResult | null => {
    const catalog = context.state.field(catalogField);
    if (!catalog.editable) return null;
    const line = context.state.doc.lineAt(context.pos);
    const match = TRIGGER.exec(line.text.slice(0, context.pos - line.from));
    if (!match) return null;

    const query = match[1].toLowerCase();
    const rank = (group: string) => {
      const at = catalog.groups.indexOf(group);
      return at < 0 ? catalog.groups.length : at;
    };
    const visible = catalog.items.filter(
      (item) => !query || item.label.toLowerCase().includes(query) || item.hint.toLowerCase().includes(query),
    );
    const ordered = [
      ...visible.filter((item) => !item.disabledReason),
      ...visible.filter((item) => item.disabledReason),
    ];
    if (ordered.length === 0) return null;

    const options: ReferenceCompletion[] = ordered.map((item) => ({
      label: item.label,
      disabled: Boolean(item.disabledReason),
      detail: item.disabledReason ?? item.hint,
      type: item.kind,
      section: { name: item.group, rank: rank(item.group) },
      apply: (view, _completion, from, to) => {
        if (item.disabledReason) return;
        const insert = `${item.token} `;
        view.dispatch({
          changes: { from, to, insert },
          selection: { anchor: from + insert.length },
          userEvent: 'input.complete',
        });
        onInsert(item);
      },
    }));

    return {
      from: context.pos - match[1].length - 1,
      options,
      filter: false,
      getMatch: (completion) => matchRange(completion.label, query),
    };
  };
}

function tooltipFor(view: EditorView, pill: Pill, from: number, to: number): Tooltip {
  return {
    pos: from,
    end: to,
    above: false,
    create: () => {
      const dom = document.createElement('div');
      dom.className = 'cm-ref-tip';

      const kind = document.createElement('div');
      kind.className = 'cm-ref-tip-kind';
      kind.textContent = KIND_NAMES[pill.ref.kind];
      dom.appendChild(kind);

      const name = document.createElement('div');
      name.className = 'cm-ref-tip-name';
      name.textContent = pill.label;
      dom.appendChild(name);

      if (pill.item?.hint) {
        const hint = document.createElement('div');
        hint.className = 'cm-ref-tip-hint';
        hint.textContent = pill.item.hint;
        dom.appendChild(hint);
      }

      const token = document.createElement('code');
      token.className = 'cm-ref-tip-token';
      token.textContent = pill.ref.token;
      dom.appendChild(token);

      if (pill.state === 'broken') {
        const note = document.createElement('div');
        note.className = 'cm-ref-tip-broken';
        note.textContent = 'This reference no longer resolves. A run fails on it — replace or remove it.';
        dom.appendChild(note);
      }

      if (view.state.field(catalogField).editable) {
        const remove = document.createElement('button');
        remove.type = 'button';
        remove.className = 'cm-ref-tip-action';
        remove.textContent = 'Remove';
        remove.addEventListener('mousedown', (event) => {
          event.preventDefault();
          const end = view.state.sliceDoc(to, to + 1) === ' ' ? to + 1 : to;
          view.dispatch({ changes: { from, to: end }, userEvent: 'delete' });
          view.focus();
        });
        dom.appendChild(remove);
      }
      return { dom };
    },
  };
}

const referenceTooltip = hoverTooltip(
  (view, pos, side) => {
    for (const ref of scanReferences(view.state.doc.toString())) {
      if (pos < ref.from || pos > ref.to) continue;
      if ((pos === ref.from && side < 0) || (pos === ref.to && side > 0)) continue;
      return tooltipFor(view, pillFor(ref, view.state.field(catalogField)), ref.from, ref.to);
    }
    return null;
  },
  { hideOnChange: true },
);

const theme = EditorView.theme({
  '&': {
    background: 'var(--app-bg-default)',
    border: '1px solid var(--app-border-default)',
    borderRadius: '5px',
    color: 'var(--app-text-primary)',
    fontSize: '14px',
    transition: 'border-color 0.12s',
  },
  '&.cm-focused': { outline: 'none', borderColor: 'var(--app-accent-muted)' },
  '&.cm-ref-readonly': { background: 'var(--app-bg-paper)', color: 'var(--app-text-secondary)' },
  '.cm-scroller': {
    fontFamily: 'inherit',
    lineHeight: '1.9',
    maxHeight: 'var(--ref-editor-max-height, 620px)',
    overflow: 'auto',
  },
  '.cm-content': {
    padding: '12px 14px',
    minHeight: 'var(--ref-editor-min-height, 180px)',
    caretColor: 'var(--app-text-primary)',
  },
  '.cm-line': { padding: 0 },
  '.cm-placeholder': { color: 'var(--app-text-tertiary)' },
  '.cm-ref-pill': {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '5px',
    padding: '0 7px 0 6px',
    margin: '0 1px',
    borderRadius: '4px',
    border: '1px solid var(--app-border-strong)',
    background: 'var(--app-bg-paper)',
    color: 'var(--app-text-primary)',
    fontSize: '13px',
    lineHeight: '20px',
    whiteSpace: 'nowrap',
    verticalAlign: 'baseline',
    cursor: 'default',
    userSelect: 'none',
  },
  '.cm-ref-pill svg': { color: 'var(--app-text-tertiary)', flexShrink: '0' },
  '.cm-ref-pill-broken': { borderColor: 'var(--app-danger-fg)', color: 'var(--app-danger-fg)' },
  '.cm-ref-pill-broken svg': { color: 'var(--app-danger-fg)' },
  '.cm-ref-pill-loading': { color: 'var(--app-text-tertiary)', borderStyle: 'dashed' },
  '.cm-tooltip': {
    background: 'var(--app-bg-paper)',
    border: '1px solid var(--app-border-default)',
    borderRadius: '8px',
    color: 'var(--app-text-primary)',
    boxShadow: '0 8px 24px rgba(0, 0, 0, 0.25)',
    overflow: 'hidden',
  },
  '.cm-tooltip.cm-tooltip-autocomplete > ul': { maxHeight: '286px', minWidth: '320px', fontFamily: 'inherit' },
  '.cm-tooltip.cm-tooltip-autocomplete > ul > completion-section': {
    display: 'block',
    padding: '8px 10px 4px',
    fontSize: '10px',
    fontWeight: '600',
    letterSpacing: '0.05em',
    textTransform: 'uppercase',
    color: 'var(--app-text-tertiary)',
    borderBottom: 'none',
  },
  '.cm-tooltip.cm-tooltip-autocomplete > ul > li': {
    display: 'flex',
    alignItems: 'baseline',
    gap: '8px',
    padding: '5px 10px',
    fontSize: '13px',
  },
  '.cm-tooltip.cm-tooltip-autocomplete > ul > li[aria-selected]': {
    background: 'var(--app-bg-hover)',
    color: 'var(--app-text-primary)',
  },
  '.cm-completionLabel': { overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' },
  '.cm-completionMatchedText': { textDecoration: 'none', fontWeight: '600', color: 'var(--app-primary-strong)' },
  '.cm-completionDetail': {
    marginLeft: 'auto',
    fontStyle: 'normal',
    fontSize: '11px',
    color: 'var(--app-text-tertiary)',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  '.cm-ref-option-disabled': { opacity: '0.5', cursor: 'not-allowed' },
  '.cm-ref-option-icon': { color: 'var(--app-text-tertiary)', alignSelf: 'center', display: 'inline-flex' },
  '.cm-ref-tip': { width: '276px', padding: '10px 12px', display: 'grid', gap: '4px', fontSize: '13px' },
  '.cm-ref-tip-kind': {
    fontSize: '10px',
    fontWeight: '600',
    letterSpacing: '0.05em',
    textTransform: 'uppercase',
    color: 'var(--app-text-tertiary)',
  },
  '.cm-ref-tip-name': { fontWeight: '600', wordBreak: 'break-all' },
  '.cm-ref-tip-hint': { color: 'var(--app-text-secondary)', fontSize: '12px' },
  '.cm-ref-tip-token': {
    fontFamily: 'monospace',
    fontSize: '11px',
    color: 'var(--app-text-tertiary)',
    wordBreak: 'break-all',
  },
  '.cm-ref-tip-broken': { color: 'var(--app-danger-fg)', fontSize: '12px' },
  '.cm-ref-tip-action': {
    justifySelf: 'start',
    marginTop: '4px',
    padding: '2px 8px',
    border: '1px solid var(--app-border-default)',
    borderRadius: '3px',
    background: 'transparent',
    color: 'var(--app-text-secondary)',
    fontSize: '12px',
    fontFamily: 'inherit',
    cursor: 'pointer',
  },
});

/** Everything that does not change while the editor lives; read-only and the catalog arrive as effects. */
export function referenceExtensions(onInsert: (item: ReferenceItem) => void): Extension[] {
  return [
    catalogField,
    pillsField,
    history(),
    autocompletion({
      override: [referenceSource(onInsert)],
      activateOnTyping: true,
      icons: false,
      optionClass: (completion) => ((completion as ReferenceCompletion).disabled ? 'cm-ref-option-disabled' : ''),
      addToOptions: [
        {
          position: 20,
          render: (completion) => {
            const icon = document.createElement('span');
            icon.className = 'cm-ref-option-icon';
            icon.appendChild(referenceIcon((completion.type as ReferenceKind | undefined) ?? 'asset'));
            return icon;
          },
        },
      ],
    }),
    keymap.of([...completionKeymap, ...defaultKeymap, ...historyKeymap]),
    referenceTooltip,
    EditorView.lineWrapping,
    theme,
  ];
}

/** Read-only still renders pills and their tooltips; it only drops editing and the picker. */
export function readOnlyExtensions(readOnly: boolean): Extension[] {
  return readOnly
    ? [
        EditorView.editable.of(false),
        EditorState.readOnly.of(true),
        EditorView.editorAttributes.of({ class: 'cm-ref-readonly' }),
      ]
    : [];
}
