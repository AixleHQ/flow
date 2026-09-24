import type { Connector } from '@/types/generated';

export type ConnectorTarget = Connector['targets'][number];
export type ConnectorInput = ConnectorTarget['inputs'][number];
