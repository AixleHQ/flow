import { readFileSync } from 'fs';

import mermaid from 'mermaid';

const input = readFileSync(0, 'utf-8');

try {
  await mermaid.parse(input);
  console.log(JSON.stringify({ valid: true }));
} catch (error) {
  console.log(JSON.stringify({ valid: false, error: error.message.replace(/\n/g, ' ') }));
}

