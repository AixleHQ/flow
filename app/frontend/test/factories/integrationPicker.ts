import type { IntegrationPicker } from '@/types/generated';

export const buildIntegrationPicker = (overrides: Partial<IntegrationPicker> = {}): IntegrationPicker => ({
  id: 1,
  name: 'Coder (alice)',
  provider: 'coder',
  status: 'active',
  host: 'coder.example.com',
  companyWide: false,
  ...overrides,
});
