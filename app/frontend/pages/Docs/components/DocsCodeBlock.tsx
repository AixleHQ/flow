import { useComputedColorScheme } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconCheck, IconCopy } from '@tabler/icons-react';
import { useState } from 'react';
import { PrismLight as SyntaxHighlighter } from 'react-syntax-highlighter';
import bash from 'react-syntax-highlighter/dist/esm/languages/prism/bash';
import css from 'react-syntax-highlighter/dist/esm/languages/prism/css';
import diff from 'react-syntax-highlighter/dist/esm/languages/prism/diff';
import docker from 'react-syntax-highlighter/dist/esm/languages/prism/docker';
import javascript from 'react-syntax-highlighter/dist/esm/languages/prism/javascript';
import json from 'react-syntax-highlighter/dist/esm/languages/prism/json';
import jsx from 'react-syntax-highlighter/dist/esm/languages/prism/jsx';
import markdown from 'react-syntax-highlighter/dist/esm/languages/prism/markdown';
import markup from 'react-syntax-highlighter/dist/esm/languages/prism/markup';
import python from 'react-syntax-highlighter/dist/esm/languages/prism/python';
import ruby from 'react-syntax-highlighter/dist/esm/languages/prism/ruby';
import sql from 'react-syntax-highlighter/dist/esm/languages/prism/sql';
import toml from 'react-syntax-highlighter/dist/esm/languages/prism/toml';
import tsx from 'react-syntax-highlighter/dist/esm/languages/prism/tsx';
import typescript from 'react-syntax-highlighter/dist/esm/languages/prism/typescript';
import yaml from 'react-syntax-highlighter/dist/esm/languages/prism/yaml';
import { oneLight, vscDarkPlus } from 'react-syntax-highlighter/dist/esm/styles/prism';

import classes from '../DocsPage.module.css';

interface Props {
  inline?: boolean;
  className?: string;
  children?: React.ReactNode;
}

// The light build with the languages the docs use, not every Prism grammar: the
// full `Prism` export bundled all of them next to the editor's own CodeMirror.
// A fence in a language not listed renders as plain text.
const GRAMMARS = {
  bash,
  css,
  diff,
  docker,
  javascript,
  json,
  jsx,
  markdown,
  markup,
  python,
  ruby,
  sql,
  toml,
  tsx,
  typescript,
  yaml,
};
for (const [name, grammar] of Object.entries(GRAMMARS)) SyntaxHighlighter.registerLanguage(name, grammar);

const ALIASES: Record<string, string> = {
  ts: 'typescript',
  js: 'javascript',
  sh: 'bash',
  shell: 'bash',
  yml: 'yaml',
  html: 'markup',
};

const LANGUAGE_LABELS: Record<string, string> = {
  typescript: 'TypeScript',
  ts: 'TypeScript',
  tsx: 'TSX',
  javascript: 'JavaScript',
  js: 'JavaScript',
  jsx: 'JSX',
  bash: 'terminal',
  sh: 'terminal',
  shell: 'terminal',
  yaml: 'YAML',
  yml: 'YAML',
  json: 'JSON',
  ruby: 'Ruby',
  python: 'Python',
  css: 'CSS',
  html: 'HTML',
  sql: 'SQL',
  text: '',
};

export function DocsCodeBlock({ inline, className, children }: Props) {
  // The syntax theme has to follow the scheme: a dark Prism theme on the light
  // canvas rendered #d4d4d4 code text at 1.4:1.
  const scheme = useComputedColorScheme('dark');
  const [copied, setCopied] = useState(false);

  const match = /language-(\w+)/.exec(className || '');
  const langKey = match ? match[1].toLowerCase() : 'text';
  const language = ALIASES[langKey] ?? langKey;
  const langLabel = LANGUAGE_LABELS[langKey] ?? langKey;
  const code = String(children).replace(/\n$/, '');

  if (inline) {
    return <code className={classes.inlineCode}>{children}</code>;
  }

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      notifications.show({ message: 'Failed to copy', color: 'red' });
    }
  };

  return (
    <div className={classes.codeBlock}>
      <div className={classes.codeHeader}>
        {langLabel && <span className={classes.codeLang}>{langLabel}</span>}
        <button
          className={`${classes.copyButton} ${copied ? classes.copyButtonCopied : ''}`}
          onClick={handleCopy}
          aria-label="Copy code to clipboard"
          type="button"
        >
          {copied ? (
            <>
              <IconCheck size={12} /> Copied
            </>
          ) : (
            <>
              <IconCopy size={12} /> Copy
            </>
          )}
        </button>
      </div>
      <SyntaxHighlighter
        language={language}
        style={scheme === 'dark' ? vscDarkPlus : oneLight}
        customStyle={{
          margin: 0,
          borderRadius: 0,
          background: 'transparent',
          fontSize: '12.5px',
          lineHeight: '1.75',
          padding: '14px 16px',
        }}
        codeTagProps={{
          style: { fontFamily: '"JetBrains Mono", monospace' },
        }}
      >
        {code}
      </SyntaxHighlighter>
    </div>
  );
}
