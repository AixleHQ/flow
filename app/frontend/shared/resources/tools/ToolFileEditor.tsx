import { css } from '@codemirror/lang-css';
import { html } from '@codemirror/lang-html';
import { javascript } from '@codemirror/lang-javascript';
import { json } from '@codemirror/lang-json';
import { markdown } from '@codemirror/lang-markdown';
import { python } from '@codemirror/lang-python';
import { sql } from '@codemirror/lang-sql';
import { yaml } from '@codemirror/lang-yaml';
import { EditorView } from '@codemirror/view';
import { Box, Text } from '@mantine/core';
import { vscodeDark } from '@uiw/codemirror-theme-vscode';
import CodeMirror from '@uiw/react-codemirror';
import { useMemo, type FC } from 'react';

interface ToolFileEditorProps {
  value: string;
  onChange: (value: string) => void;
  path: string;
}

const getExtension = (path: string): string => {
  const match = path.match(/\.([^.]+)$/);
  return match ? match[1].toLowerCase() : '';
};

const getLanguageExtension = (ext: string) => {
  switch (ext) {
    case 'js':
    case 'jsx':
      return javascript({ jsx: true });
    case 'ts':
    case 'tsx':
      return javascript({ jsx: true, typescript: true });
    case 'py':
      return python();
    case 'json':
      return json();
    case 'html':
    case 'htm':
      return html();
    case 'css':
    case 'scss':
    case 'less':
      return css();
    case 'md':
    case 'markdown':
      return markdown();
    case 'sql':
      return sql();
    case 'yml':
    case 'yaml':
      return yaml();
    default:
      return [];
  }
};

export const ToolFileEditor: FC<ToolFileEditorProps> = ({ value, onChange, path }) => {
  const ext = useMemo(() => getExtension(path), [path]);
  const extensions = useMemo(() => {
    const langExt = getLanguageExtension(ext);
    return [EditorView.lineWrapping, ...(Array.isArray(langExt) ? langExt : [langExt])];
  }, [ext]);

  return (
    <Box>
      <Text fz={12} c="dimmed" mb={4}>
        Content
      </Text>
      <Box
        style={{
          border: '1px solid var(--app-border-default)',
          borderRadius: 'var(--mantine-radius-sm)',
          overflow: 'hidden',
        }}
      >
        <CodeMirror
          value={value}
          onChange={onChange}
          theme={vscodeDark}
          extensions={extensions}
          height="200px"
          placeholder="# File content..."
          basicSetup={{
            lineNumbers: true,
            foldGutter: true,
            highlightActiveLine: true,
            autocompletion: false,
          }}
        />
      </Box>
    </Box>
  );
};
