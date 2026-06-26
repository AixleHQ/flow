import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { ConfigItemValueField } from './ConfigItemValueField';

describe('ConfigItemValueField', () => {
  it('renders a plain text input with the label by default and shows the "use config items" toggle', () => {
    renderPage(
      <ConfigItemValueField value="" onChange={vi.fn()} configItemNames={['API_KEY', 'DB_URL']} label="Secret" />,
    );

    // Plain text mode: labelled TextInput is present.
    expect(screen.getByRole('textbox', { name: 'Secret' })).toBeInTheDocument();
    // The toggle to switch into config-item mode is present (button has the tooltip label as its accessible name).
    expect(screen.getByRole('button')).toBeInTheDocument();
  });

  it('fires onChange with the typed text in plain text mode', async () => {
    const onChange = vi.fn();
    renderPage(<ConfigItemValueField value="" onChange={onChange} configItemNames={[]} label="Secret" />);

    await userEvent.type(screen.getByRole('textbox', { name: 'Secret' }), 'x');

    expect(onChange).toHaveBeenCalledWith('x');
  });

  it('clicking the toggle clears the current value (onChange "")', async () => {
    const onChange = vi.fn();
    renderPage(<ConfigItemValueField value="hello" onChange={onChange} configItemNames={[]} label="Secret" />);

    await userEvent.click(screen.getByRole('button'));

    expect(onChange).toHaveBeenCalledWith('');
  });

  it('renders the config-item autocomplete (not a plain text box) when the value is a config_item reference', () => {
    renderPage(
      <ConfigItemValueField
        value="config_item:API_KEY"
        onChange={vi.fn()}
        configItemNames={['API_KEY', 'DB_URL']}
        label="Secret"
      />,
    );

    // Config-item mode: the Autocomplete shows its own placeholder and is pre-filled with the referenced name.
    const input = screen.getByPlaceholderText('Select config item...');
    expect(input).toBeInTheDocument();
    expect(input).toHaveValue('API_KEY');
  });

  it('editing the autocomplete in config-item mode fires onChange with the config_item: prefix', async () => {
    const onChange = vi.fn();
    renderPage(
      <ConfigItemValueField
        value="config_item:"
        onChange={onChange}
        configItemNames={['API_KEY']}
        label="Secret"
      />,
    );

    await userEvent.type(screen.getByPlaceholderText('Select config item...'), 'D');

    expect(onChange).toHaveBeenCalledWith('config_item:D');
  });
});
