import '@testing-library/jest-dom/vitest';
import { screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { buildLlmCall } from 'test/factories/llmCall';
import { renderPage } from 'test/renderPage';

import LlmCallsTable from './LlmCallsTable';

describe('LlmCallsTable', () => {
  it('renders a row for each call', () => {
    const calls = [
      buildLlmCall({ id: 1, model: 'claude-sonnet-4-5' }),
      buildLlmCall({ id: 2, model: 'claude-haiku-4-5' }),
    ];
    renderPage(<LlmCallsTable calls={calls} showSessionColumn />);
    expect(screen.getAllByRole('row')).toHaveLength(3); // header + 2 data rows
  });

  it('shows Session column when showSessionColumn is true', () => {
    renderPage(<LlmCallsTable calls={[buildLlmCall()]} showSessionColumn />);
    expect(screen.getByRole('columnheader', { name: /session/i })).toBeInTheDocument();
    expect(screen.getByText('Post QA report')).toBeInTheDocument();
  });

  it('hides Session column when showSessionColumn is false', () => {
    renderPage(<LlmCallsTable calls={[buildLlmCall()]} showSessionColumn={false} />);
    expect(screen.queryByRole('columnheader', { name: /session/i })).not.toBeInTheDocument();
  });

  it('renders model name in each row', () => {
    renderPage(<LlmCallsTable calls={[buildLlmCall({ model: 'claude-sonnet-4-5' })]} showSessionColumn />);
    expect(screen.getByText('claude-sonnet-4-5')).toBeInTheDocument();
  });

  it('renders cost formatted via formatCostCents', () => {
    renderPage(<LlmCallsTable calls={[buildLlmCall({ costCents: 150 })]} showSessionColumn />);
    expect(screen.getByText('$1.50')).toBeInTheDocument();
  });

  it('renders empty state when no calls', () => {
    renderPage(<LlmCallsTable calls={[]} showSessionColumn />);
    expect(screen.getByText('No LLM calls recorded')).toBeInTheDocument();
  });
});
