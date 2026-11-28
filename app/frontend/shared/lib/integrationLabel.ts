import type { IntegrationPicker } from '@/types/generated';

/** How a picker names an integration: its name, provider and, for Coder, host, so alike names tell apart. */
export function integrationLabel(integration: IntegrationPicker): string {
  const where = integration.host ? `${integration.provider} @ ${integration.host}` : integration.provider;
  const status = integration.status === 'active' ? '' : `, ${integration.status}`;
  return `${integration.name} (${where}${status})`;
}
