// Shapes served by ConnectorResource. Camel-cased on the wire by the app's
// standard key transform, so these mirror the resource's attributes rather than
// the registry's own vocabulary — nothing here should ever need to know what
// `server.json` looks like.

export interface ConnectorInput {
  key: string;
  /** Where the value ends up: 'header' | 'env' | 'arg'. */
  kind: string;
  description: string | null;
  /** 'string' | 'number' | 'boolean' | 'filepath' */
  format: string;
  required: boolean;
  secret: boolean;
  default: string | null;
  choices: string[] | null;
  placeholder: string | null;
  repeated: boolean;
}

export interface ConnectorTarget {
  /** Stable id submitted on install; the server re-resolves it against a live manifest. */
  id: string;
  /** 'remote' | 'package' */
  kind: string;
  /** 'http' | 'sse' | 'stdio' */
  transport: string;
  supported: boolean;
  /** Why this option cannot be installed here, when supported is false. */
  unsupportedReason: string | null;
  url: string | null;
  registryType: string | null;
  identifier: string | null;
  /** The exact launch line for a package target, e.g. "npx @scope/pkg@1.2.3". */
  command: string | null;
  version: string | null;
  versionPinned: boolean;
  runtime: string | null;
  runtimePrefixArgs: string[];
  inputs: ConnectorInput[];
}

export interface Connector {
  id: number;
  name: string;
  title: string | null;
  pickerName: string;
  /** Derived from the registry namespace; null when it yields nothing usable. */
  iconUrl: string | null;
  /** The registry verified this publisher owns the domain. */
  vendorPublished: boolean;
  description: string | null;
  version: string | null;
  repositoryUrl: string | null;
  /** 'active' | 'deprecated' | 'deleted' */
  status: string;
  installable: boolean;
  targets: ConnectorTarget[];
  registryUpdatedAt: string | null;
  createdAt: string;
  updatedAt: string;
}
