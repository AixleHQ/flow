import { Annotation, Compartment, EditorState } from '@codemirror/state';
import { EditorView, placeholder as placeholderExtension } from '@codemirror/view';
import { type CSSProperties, useEffect, useLayoutEffect, useRef } from 'react';

import {
  readOnlyExtensions,
  referenceExtensions,
  type ReferenceItem,
  setReferenceCatalog,
} from './referenceExtensions';

export type { ReferenceItem } from './referenceExtensions';

interface ReferenceEditorProps {
  /** The stored text, tokens included. */
  value: string;
  onChange: (value: string) => void;
  items: readonly ReferenceItem[];
  /** Menu sections, in display order. */
  groups: readonly string[];
  /** The catalog is still on its way: unknown tokens render neutral, not broken. */
  loading?: boolean;
  readOnly?: boolean;
  /** Called after a picked reference was written into the text. */
  onInsert?: (item: ReferenceItem) => void;
  placeholder?: string;
  ariaLabel: string;
  minHeight?: number;
  /** null lets the editor grow without an inner scrollbar. */
  maxHeight?: number | null;
}

// Marks the transactions that copy a new `value` prop in, so they are not echoed back to onChange.
const external = Annotation.define<boolean>();

/**
 * A plain-text editor whose `{{asset:12}}`-style tokens render as pills and that offers an `@`
 * picker over `items`. The document is the stored string, so what is saved is exactly what is shown
 * as text, and a token pasted as text becomes a pill on its own.
 */
export function ReferenceEditor({
  value,
  onChange,
  items,
  groups,
  loading = false,
  readOnly = false,
  onInsert,
  placeholder,
  ariaLabel,
  minHeight = 180,
  maxHeight = 620,
}: ReferenceEditorProps) {
  const hostRef = useRef<HTMLDivElement>(null);
  const viewRef = useRef<EditorView | null>(null);
  const onChangeRef = useRef(onChange);
  const onInsertRef = useRef(onInsert);
  const readOnlyCompartment = useRef(new Compartment());
  const initial = useRef({ value, readOnly, placeholder, ariaLabel });

  useLayoutEffect(() => {
    onChangeRef.current = onChange;
    onInsertRef.current = onInsert;
  });

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;
    const { value: doc, readOnly: ro, placeholder: hint, ariaLabel: label } = initial.current;
    const view = new EditorView({
      parent: host,
      state: EditorState.create({
        doc,
        extensions: [
          referenceExtensions((item) => onInsertRef.current?.(item)),
          readOnlyCompartment.current.of(readOnlyExtensions(ro)),
          hint ? placeholderExtension(hint) : [],
          EditorView.contentAttributes.of({ 'aria-label': label, 'aria-multiline': 'true' }),
          EditorView.updateListener.of((update) => {
            if (!update.docChanged) return;
            if (update.transactions.some((tr) => tr.annotation(external))) return;
            onChangeRef.current(update.state.doc.toString());
          }),
        ],
      }),
    });
    viewRef.current = view;
    return () => {
      view.destroy();
      viewRef.current = null;
    };
  }, []);

  useEffect(() => {
    const view = viewRef.current;
    if (!view) return;
    const current = view.state.doc.toString();
    if (current === value) return;
    view.dispatch({ changes: { from: 0, to: current.length, insert: value }, annotations: external.of(true) });
  }, [value]);

  useEffect(() => {
    viewRef.current?.dispatch({
      effects: setReferenceCatalog.of({ items, groups, loading, editable: !readOnly }),
    });
  }, [items, groups, loading, readOnly]);

  useEffect(() => {
    viewRef.current?.dispatch({ effects: readOnlyCompartment.current.reconfigure(readOnlyExtensions(readOnly)) });
  }, [readOnly]);

  const style = {
    '--ref-editor-min-height': `${minHeight}px`,
    '--ref-editor-max-height': maxHeight == null ? 'none' : `${maxHeight}px`,
  } as CSSProperties;

  return <div ref={hostRef} style={style} />;
}
