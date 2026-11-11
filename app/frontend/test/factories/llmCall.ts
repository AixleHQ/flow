import type LlmCall from '@/types/generated/LlmCall';

export const buildLlmCall = (overrides: Partial<LlmCall> = {}): LlmCall => ({
  id: 1,
  model: 'claude-sonnet-4-5',
  provider: 'anthropic',
  inputTokens: 1200,
  outputTokens: 450,
  cacheReadTokens: 100,
  cacheWriteTokens: 50,
  costCents: 0.0451,
  costBasis: 'reported',
  occurredAt: '2026-08-28T10:00:00.000Z',
  stepRunId: 10,
  stepName: 'Post QA report',
  source: 'otlp_log',
  granularity: 'request',
  ...overrides,
});
