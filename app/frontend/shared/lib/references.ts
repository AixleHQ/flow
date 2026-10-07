// `@` reference tokens in instruction text (docs/design/at-references.md §2). The same grammar is
// parsed by the server (InstructionReferences), which renders each token into a path or a name
// when a session starts — change one side only together with the other.

export type ReferenceKind = 'asset' | 'output' | 'step' | 'mcp';

export interface ParsedReference {
  kind: ReferenceKind;
  token: string;
  from: number;
  to: number;
  /** False when the body does not parse: the token is shown broken, never as plain text. */
  valid: boolean;
  /** Asset or MCP server id. */
  id?: number;
  /** A step id, or `new-<n>` for a step that is not saved yet. */
  stepRef?: string;
  /** Output spec name. */
  name?: string;
}

const TOKEN_SOURCE = String.raw`\{\{(asset|output|step|mcp):([^{}\n]+?)\}\}`;
const ID = /^[1-9]\d*$/;
const STEP_REF = /^(?:[1-9]\d*|new-[1-9]\d*)$/;

function parseBody(kind: ReferenceKind, body: string): Omit<ParsedReference, 'kind' | 'token' | 'from' | 'to'> {
  switch (kind) {
    case 'asset':
    case 'mcp':
      return ID.test(body) ? { valid: true, id: Number(body) } : { valid: false };
    case 'step':
      return STEP_REF.test(body) ? { valid: true, stepRef: body } : { valid: false };
    case 'output': {
      const colon = body.indexOf(':');
      const stepRef = colon < 0 ? body : body.slice(0, colon);
      const name = colon < 0 ? '' : body.slice(colon + 1);
      return STEP_REF.test(stepRef) && name.length > 0 ? { valid: true, stepRef, name } : { valid: false };
    }
  }
}

/** Every reference token in `text`, in order. */
export function scanReferences(text: string): ParsedReference[] {
  const found: ParsedReference[] = [];
  for (const match of text.matchAll(new RegExp(TOKEN_SOURCE, 'g'))) {
    const kind = match[1] as ReferenceKind;
    const from = match.index ?? 0;
    found.push({ kind, token: match[0], from, to: from + match[0].length, ...parseBody(kind, match[2]) });
  }
  return found;
}

export const referenceToken = {
  asset: (id: number) => `{{asset:${id}}}`,
  mcp: (id: number) => `{{mcp:${id}}}`,
  step: (stepRef: string) => `{{step:${stepRef}}}`,
  output: (stepRef: string, name: string) => `{{output:${stepRef}:${name}}}`,
};

/** A reference that does not resolve, labelled by what it was meant to name. */
export function brokenReferenceLabel(ref: ParsedReference): string {
  if (!ref.valid) return 'Invalid reference';
  switch (ref.kind) {
    case 'asset':
      return `Missing asset #${ref.id}`;
    case 'mcp':
      return `Missing MCP server #${ref.id}`;
    case 'step':
      return 'Missing session';
    case 'output':
      return `Undeclared output ${ref.name}`;
  }
}

/** Points every output reference of one step at its renamed spec. */
export function renameOutputReferences(text: string, stepRef: string, oldName: string, newName: string): string {
  if (oldName === newName) return text;
  const oldToken = referenceToken.output(stepRef, oldName);
  return scanReferences(text)
    .filter((ref) => ref.token === oldToken)
    .reverse()
    .reduce((acc, ref) => acc.slice(0, ref.from) + referenceToken.output(stepRef, newName) + acc.slice(ref.to), text);
}
