import { notifications } from '@mantine/notifications';
import { IconCheck, IconCopy } from '@tabler/icons-react';
import { useState } from 'react';
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { vscDarkPlus } from 'react-syntax-highlighter/dist/esm/styles/prism';

import classes from '../DocsPage.module.css';

interface Props {
  inline?: boolean;
  className?: string;
  children?: React.ReactNode;
}

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
  const [copied, setCopied] = useState(false);

  const match = /language-(\w+)/.exec(className || '');
  const langKey = match ? match[1].toLowerCase() : 'text';
  const language = langKey;
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
        style={vscDarkPlus}
        customStyle={{
          margin: 0,
          borderRadius: 0,
          background: 'transparent',
          fontSize: '12.5px',
          lineHeight: '1.75',
          padding: '14px 16px',
        }}
        codeTagProps={{
          style: { fontFamily: '"Geist Mono", monospace' },
        }}
      >
        {code}
      </SyntaxHighlighter>
    </div>
  );
}
