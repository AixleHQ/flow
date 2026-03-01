import { css } from '@codemirror/lang-css';
import { html } from '@codemirror/lang-html';
import { javascript } from '@codemirror/lang-javascript';
import { json } from '@codemirror/lang-json';
import { markdown } from '@codemirror/lang-markdown';
import { python } from '@codemirror/lang-python';
import { sql } from '@codemirror/lang-sql';
import { yaml } from '@codemirror/lang-yaml';
import { EditorView } from '@codemirror/view';
import AddIcon from '@mui/icons-material/Add';
import CloudUploadIcon from '@mui/icons-material/CloudUpload';
import DeleteIcon from '@mui/icons-material/Delete';
import InsertDriveFileIcon from '@mui/icons-material/InsertDriveFile';
import {
  Box,
  Button,
  IconButton,
  Paper,
  Stack,
  TextField,
  ToggleButton,
  ToggleButtonGroup,
  Typography,
  type SxProps,
} from '@mui/material';
import { vscodeDark } from '@uiw/codemirror-theme-vscode';
import CodeMirror from '@uiw/react-codemirror';
import { type FC, useCallback, useMemo, useRef, useState } from 'react';
import { Controller, useFieldArray, useFormContext, useWatch } from 'react-hook-form';

import type { ToolFormData } from '../lib/toolSchema';

const styles = {
  container: {
    p: 2,
    backgroundColor: 'background.base',
    borderRadius: 1,
  },
  fileItem: {
    p: 2,
    backgroundColor: 'background.surface',
    borderRadius: 1,
    border: '1px solid',
    borderColor: 'border.defaultAlt',
  },
  pathField: {
    fontFamily: '"JetBrains Mono", monospace',
  },
  editorWrapper: {
    mt: 1,
    border: '1px solid',
    borderColor: 'border.defaultAlt',
    borderRadius: 1,
    overflow: 'hidden',
  },
  editorLabel: {
    fontSize: 12,
    color: 'text.secondary',
    mb: 0.5,
  },
  uploadZone: {
    mt: 1,
    p: 3,
    border: '2px dashed',
    borderColor: 'border.defaultAlt',
    borderRadius: 1,
    textAlign: 'center',
    cursor: 'pointer',
    transition: 'border-color 0.2s, background-color 0.2s',
    '&:hover': {
      borderColor: 'primary.main',
      backgroundColor: 'action.hover',
    },
  },
  uploadedFile: {
    mt: 1,
    p: 2,
    display: 'flex',
    alignItems: 'center',
    gap: 1.5,
    border: '1px solid',
    borderColor: 'border.defaultAlt',
    borderRadius: 1,
    backgroundColor: 'background.base',
  },
} satisfies Record<string, SxProps | object>;

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

const formatFileSize = (bytes: number): string => {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
};

type FileMode = 'text' | 'upload';

interface FileEditorProps {
  index: number;
}

const FileEditor: FC<FileEditorProps> = ({ index }) => {
  const { control, setValue, getValues } = useFormContext<ToolFormData>();
  const path = useWatch({ control, name: `toolFilesAttributes.${index}.path` }) || '';
  const existingFileUrl = useWatch({ control, name: `toolFilesAttributes.${index}.existingFileUrl` });
  const existingFileName = useWatch({ control, name: `toolFilesAttributes.${index}.existingFileName` });
  const currentFile = useWatch({ control, name: `toolFilesAttributes.${index}.file` });

  const initialMode: FileMode = existingFileUrl || currentFile ? 'upload' : 'text';
  const [mode, setMode] = useState<FileMode>(initialMode);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const ext = useMemo(() => getExtension(path), [path]);
  const extensions = useMemo(() => {
    const langExt = getLanguageExtension(ext);
    return [EditorView.lineWrapping, ...(Array.isArray(langExt) ? langExt : [langExt])];
  }, [ext]);

  const handleModeChange = useCallback((_: unknown, newMode: FileMode | null) => {
    if (!newMode) return;
    setMode(newMode);
  }, []);

  const handleFileSelect = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (!file) return;
      setValue(`toolFilesAttributes.${index}.file`, file, { shouldValidate: true });
      setValue(`toolFilesAttributes.${index}.existingFileUrl`, undefined);
      setValue(`toolFilesAttributes.${index}.existingFileName`, undefined);
      setValue(`toolFilesAttributes.${index}.content`, '');

      const currentPath = getValues(`toolFilesAttributes.${index}.path`);
      if (!currentPath || currentPath === '/workspace/') {
        setValue(`toolFilesAttributes.${index}.path`, `/workspace/${file.name}`);
      }
    },
    [index, setValue, getValues],
  );

  const displayFile = currentFile || (existingFileUrl ? { name: existingFileName || 'uploaded file' } : null);

  return (
    <Box>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
        <Typography sx={styles.editorLabel}>Content</Typography>
        <ToggleButtonGroup size="small" value={mode} exclusive onChange={handleModeChange} sx={{ height: 24 }}>
          <ToggleButton value="text" sx={{ fontSize: 11, px: 1, py: 0 }}>
            Text
          </ToggleButton>
          <ToggleButton value="upload" sx={{ fontSize: 11, px: 1, py: 0 }}>
            Upload
          </ToggleButton>
        </ToggleButtonGroup>
      </Box>

      {mode === 'text' ? (
        <Controller
          name={`toolFilesAttributes.${index}.content`}
          control={control}
          render={({ field, fieldState }) => (
            <Box>
              <Box sx={styles.editorWrapper}>
                <CodeMirror
                  value={field.value || ''}
                  onChange={field.onChange}
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
              {fieldState.error && (
                <Typography sx={{ color: 'error.main', fontSize: 12, mt: 0.5 }}>{fieldState.error.message}</Typography>
              )}
            </Box>
          )}
        />
      ) : (
        <Box>
          <input ref={fileInputRef} type="file" hidden onChange={handleFileSelect} />
          {displayFile ? (
            <Box sx={styles.uploadedFile}>
              <InsertDriveFileIcon sx={{ color: 'primary.main', fontSize: 28 }} />
              <Box sx={{ flex: 1, minWidth: 0 }}>
                <Typography sx={{ fontSize: 13, fontWeight: 500, overflow: 'hidden', textOverflow: 'ellipsis' }}>
                  {displayFile instanceof File ? displayFile.name : displayFile.name}
                </Typography>
                {displayFile instanceof File && (
                  <Typography sx={{ fontSize: 11, color: 'text.secondary' }}>
                    {formatFileSize(displayFile.size)}
                  </Typography>
                )}
                {existingFileUrl && !(displayFile instanceof File) && (
                  <Typography sx={{ fontSize: 11, color: 'text.secondary' }}>Previously uploaded</Typography>
                )}
              </Box>
              <Button size="small" variant="outlined" onClick={() => fileInputRef.current?.click()}>
                Replace
              </Button>
            </Box>
          ) : (
            <Box sx={styles.uploadZone} onClick={() => fileInputRef.current?.click()}>
              <CloudUploadIcon sx={{ fontSize: 36, color: 'text.disabled', mb: 0.5 }} />
              <Typography sx={{ fontSize: 13, color: 'text.secondary' }}>
                Click to select a file (binary or text)
              </Typography>
            </Box>
          )}
        </Box>
      )}
    </Box>
  );
};

const ToolFilesEditor: FC = () => {
  const { control } = useFormContext<ToolFormData>();
  const { fields, append, remove } = useFieldArray({
    control,
    name: 'toolFilesAttributes',
  });

  const handleAddFile = () => {
    append({ path: '/workspace/', content: '' });
  };

  return (
    <Box sx={styles.container}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
        <Typography variant="subtitle2" sx={{ color: 'text.secondary' }}>
          Files to Mount
        </Typography>
        <Button size="small" startIcon={<AddIcon />} onClick={handleAddFile}>
          Add File
        </Button>
      </Box>

      {fields.length === 0 ? (
        <Typography sx={{ color: 'text.disabled', fontSize: 13, textAlign: 'center', py: 2 }}>
          No files. Add files to mount into the container.
        </Typography>
      ) : (
        <Stack spacing={2}>
          {fields.map((field, index) => (
            <Paper key={field.id} sx={styles.fileItem} elevation={0}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 1 }}>
                <Controller
                  name={`toolFilesAttributes.${index}.path`}
                  control={control}
                  render={({ field: pathField, fieldState }) => (
                    <TextField
                      {...pathField}
                      label="Path"
                      placeholder="/workspace/script.py"
                      size="small"
                      sx={{ flex: 1, mr: 1, ...styles.pathField }}
                      error={!!fieldState.error}
                      helperText={fieldState.error?.message || 'Must start with /workspace/'}
                    />
                  )}
                />
                <IconButton size="small" onClick={() => remove(index)} sx={{ color: 'error.main', mt: 0.5 }}>
                  <DeleteIcon fontSize="small" />
                </IconButton>
              </Box>
              <FileEditor index={index} />
            </Paper>
          ))}
        </Stack>
      )}
    </Box>
  );
};

export { ToolFilesEditor };
