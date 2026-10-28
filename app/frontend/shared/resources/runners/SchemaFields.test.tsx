import '@testing-library/jest-dom/vitest';
import { useState } from 'react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import type { JsonSchema, RunnerConfig } from './runnerConfig';
import { SchemaFields } from './SchemaFields';

// An object without `properties` (like the coder `parameters` key) has no widget and falls back to JSON.
const schema: JsonSchema = {
  type: 'object',
  properties: { parameters: { type: 'object', default: {} } },
};

function Harness({ initial }: { initial: RunnerConfig }) {
  const [config, setConfig] = useState<RunnerConfig>(initial);
  return (
    <>
      <SchemaFields schema={schema} config={config} onChange={setConfig} errors={{}} />
      <output data-testid="config">{JSON.stringify(config)}</output>
    </>
  );
}

describe('SchemaFields JSON fallback', () => {
  it('clears its text when "Use default" unsets the key, so the old JSON is not sent again', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<Harness initial={{ parameters: { region: 'eu' } }} />);

    const field = screen.getByRole('textbox', { name: /^Parameters/ });
    expect(field).toHaveValue(JSON.stringify({ region: 'eu' }, null, 2));

    await user.click(screen.getByRole('button', { name: 'Use the default for Parameters' }));

    expect(screen.getByTestId('config')).toHaveTextContent(/^\{\}$/);
    expect(field).toHaveValue('');

    // Focusing and leaving the field must not bring the old value back.
    await user.click(field);
    await user.tab();
    expect(screen.getByTestId('config')).toHaveTextContent(/^\{\}$/);
  });

  it('keeps what the user typed once it parses and commits it', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<Harness initial={{}} />);

    const field = screen.getByRole('textbox', { name: /^Parameters/ });
    await user.click(field);
    await user.paste('{"size": 2}');
    await user.tab();

    expect(screen.getByTestId('config')).toHaveTextContent('{"parameters":{"size":2}}');
    expect(field).toHaveValue('{"size": 2}');
  });
});
