import { router } from '@inertiajs/react';
import {
  ActionIcon,
  Anchor,
  Box,
  Button,
  Group,
  Modal,
  MultiSelect,
  SegmentedControl,
  Stack,
  Tabs,
  Text,
  TextInput,
  Textarea,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { IconCode, IconDownload, IconFile, IconPlus, IconTrash, IconUpload } from '@tabler/icons-react';
import { zod4Resolver as zodResolver } from 'mantine-form-zod-resolver';
import { useCallback, useEffect, useRef, useState, type FC } from 'react';
import { z } from 'zod';

import { ToolFileEditor } from './ToolFileEditor';

const toolSchema = z.object({
  name: z
    .string()
    .min(1, 'Name is required')
    .max(100)
    .regex(/^[a-z][a-z0-9_]*$/, 'Must start with letter, lowercase + underscores only'),
  displayName: z.string().min(1, 'Display name is required').max(200),
  description: z.string().max(2000).optional(),
  dockerImage: z.string().min(1, 'Docker image is required'),
  command: z.string().max(2000).optional(),
  requiredConfigItems: z.array(z.string()).optional(),
});

interface ToolFile {
  id?: number;
  path: string;
  content: string;
  binary: boolean;
  fileName: string | null;
  fileUrl: string | null;
}

interface Tool {
  id: number;
  name: string;
  displayName: string;
  description: string | null;
  dockerImage: string | null;
  command: string | null;
  requiredConfigItems: string[];
  inputSchema: Record<string, unknown>;
  scopeType: string | null;
  toolFiles: ToolFile[];
}

type FileMode = 'text' | 'upload';

interface FileEntry {
  id?: number;
  path: string;
  content: string;
  mode: FileMode;
  file?: File;
  existingFileName?: string | null;
  existingFileUrl?: string | null;
  _destroy?: boolean;
}

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

interface ToolFormModalProps {
  opened: boolean;
  onClose: () => void;
  editTool?: Tool | null;
  configItemNames: string[];
  basePath: string;
}

export const ToolFormModal: FC<ToolFormModalProps> = ({ opened, onClose, editTool, configItemNames, basePath }) => {
  const [submitting, setSubmitting] = useState(false);
  const [activeTab, setActiveTab] = useState<string | null>('basic');
  const [files, setFiles] = useState<FileEntry[]>([]);
  const fileInputRefs = useRef<Record<number, HTMLInputElement | null>>({});
  const isEditMode = !!editTool;

  const form = useForm({
    validate: zodResolver(toolSchema),
    initialValues: {
      name: '',
      displayName: '',
      description: '',
      dockerImage: '',
      command: '',
      requiredConfigItems: [] as string[],
    },
  });

  useEffect(() => {
    if (opened) {
      setActiveTab('basic');
      if (editTool) {
        form.setValues({
          name: editTool.name,
          displayName: editTool.displayName,
          description: editTool.description || '',
          dockerImage: editTool.dockerImage || '',
          command: editTool.command || '',
          requiredConfigItems: editTool.requiredConfigItems || [],
        });
        setFiles(
          editTool.toolFiles.map((f) => ({
            id: f.id,
            path: f.path,
            content: f.content || '',
            mode: (f.binary ? 'upload' : 'text') as FileMode,
            existingFileName: f.fileName,
            existingFileUrl: f.fileUrl,
          })),
        );
      } else {
        form.reset();
        setFiles([]);
      }
    }
  }, [opened, editTool]);

  const hasFileUploads = useCallback(
    () => files.some((f) => !f._destroy && f.mode === 'upload' && f.file instanceof File),
    [files],
  );

  const buildFormData = useCallback(
    (values: typeof form.values): FormData => {
      const fd = new FormData();

      fd.append('tool[name]', values.name);
      fd.append('tool[display_name]', values.displayName);
      fd.append('tool[description]', values.description || '');
      fd.append('tool[docker_image]', values.dockerImage);
      fd.append('tool[command]', values.command || '');
      (values.requiredConfigItems || []).forEach((item) => {
        fd.append('tool[required_config_items][]', item);
      });
      if (!values.requiredConfigItems?.length) {
        fd.append('tool[required_config_items][]', '');
      }

      const activeFiles = files.filter((f) => !f._destroy);
      const deletedFiles = files.filter((f) => f._destroy && f.id);

      activeFiles.forEach((f, i) => {
        const prefix = `tool[tool_files_attributes][${i}]`;
        if (f.id) fd.append(`${prefix}[id]`, String(f.id));
        fd.append(`${prefix}[path]`, f.path);

        if (f.mode === 'upload' && f.file instanceof File) {
          fd.append(`${prefix}[file]`, f.file);
          fd.append(`${prefix}[content]`, '');
        } else if (f.mode === 'text') {
          fd.append(`${prefix}[content]`, f.content);
        }
      });

      deletedFiles.forEach((f, i) => {
        const idx = activeFiles.length + i;
        const prefix = `tool[tool_files_attributes][${idx}]`;
        fd.append(`${prefix}[id]`, String(f.id));
        fd.append(`${prefix}[_destroy]`, '1');
      });

      return fd;
    },
    [files],
  );

  const handleSubmit = (values: typeof form.values) => {
    const activeFiles = files.filter((f) => !f._destroy);

    const hasInvalidPaths = activeFiles.some((f) => !f.path.startsWith('/workspace/'));
    if (hasInvalidPaths) {
      setActiveTab('files');
      return;
    }

    const uploadFileMissing = activeFiles.some((f) => f.mode === 'upload' && !f.file && !f.existingFileUrl);
    if (uploadFileMissing) {
      setActiveTab('files');
      return;
    }

    setSubmitting(true);

    const callbacks = {
      preserveScroll: true,
      forceFormData: true as const,
      onSuccess: () => {
        setSubmitting(false);
        onClose();
      },
      onError: (errors: Record<string, string>) => {
        setSubmitting(false);
        Object.entries(errors).forEach(([key, message]) => {
          form.setFieldError(key, message);
        });
      },
    };

    if (hasFileUploads()) {
      const fd = buildFormData(values);

      if (isEditMode && editTool) {
        fd.append('_method', 'PATCH');
        router.post(`${basePath}/${editTool.id}`, fd, callbacks);
      } else {
        router.post(basePath, fd, callbacks);
      }
    } else {
      const deletedFiles = files.filter((f) => f._destroy && f.id);
      const toolFilesAttributes = [
        ...activeFiles.map((f) => ({
          id: f.id || undefined,
          path: f.path,
          content: f.content,
        })),
        ...deletedFiles.map((f) => ({
          id: f.id,
          _destroy: '1' as const,
        })),
      ];

      const data = {
        tool: {
          ...values,
          toolFilesAttributes,
        },
      } as Record<string, unknown>;

      if (isEditMode && editTool) {
        router.patch(`${basePath}/${editTool.id}`, data as never, callbacks);
      } else {
        router.post(basePath, data as never, callbacks);
      }
    }
  };

  const handleAddFile = () => {
    setFiles((prev) => [...prev, { path: '/workspace/', content: '', mode: 'text' }]);
  };

  const handleRemoveFile = (index: number) => {
    setFiles((prev) => {
      const file = prev[index];
      if (file.id) {
        return prev.map((f, i) => (i === index ? { ...f, _destroy: true } : f));
      }
      return prev.filter((_, i) => i !== index);
    });
  };

  const handleFileChange = (index: number, field: 'path' | 'content', value: string) => {
    setFiles((prev) => prev.map((f, i) => (i === index ? { ...f, [field]: value } : f)));
  };

  const handleModeChange = (index: number, mode: FileMode) => {
    setFiles((prev) => prev.map((f, i) => (i === index ? { ...f, mode, file: undefined, content: '' } : f)));
  };

  const handleFileUpload = (index: number, uploadedFile: File | null) => {
    if (!uploadedFile) return;
    setFiles((prev) =>
      prev.map((f, i) =>
        i === index ? { ...f, file: uploadedFile, existingFileName: null, existingFileUrl: null } : f,
      ),
    );
  };

  const handleNameChange = (value: string) => {
    form.setFieldValue('name', value.toLowerCase().replace(/[^a-z0-9_]/g, '_'));
  };

  const visibleFiles = files.filter((f) => !f._destroy);

  return (
    <Modal opened={opened} onClose={onClose} title={isEditMode ? 'Edit Tool' : 'Create Tool'} size="lg" centered>
      <form onSubmit={form.onSubmit(handleSubmit)}>
        <Tabs value={activeTab} onChange={setActiveTab} mb="md">
          <Tabs.List>
            <Tabs.Tab value="basic">Basic Info</Tabs.Tab>
            <Tabs.Tab value="files">Files ({visibleFiles.length})</Tabs.Tab>
            <Tabs.Tab value="config">Secrets</Tabs.Tab>
          </Tabs.List>

          <Tabs.Panel value="basic" pt="md">
            <Stack gap="md">
              <TextInput
                {...form.getInputProps('name')}
                onChange={(e) => handleNameChange(e.currentTarget.value)}
                label="Name"
                placeholder="my_tool"
                description="Unique identifier (lowercase, underscores)"
                autoFocus
                disabled={isEditMode}
                styles={{ input: { fontFamily: '"JetBrains Mono", monospace' } }}
              />

              <TextInput
                {...form.getInputProps('displayName')}
                label="Display Name"
                placeholder="My Custom Tool"
                description="Human-readable name"
              />

              <Textarea
                {...form.getInputProps('description')}
                label="Description"
                placeholder="What this tool does..."
                minRows={2}
                autosize
              />

              <TextInput
                {...form.getInputProps('dockerImage')}
                label="Docker Image"
                placeholder="python:3.11-slim"
                description="Docker image to run"
                styles={{ input: { fontFamily: '"JetBrains Mono", monospace' } }}
              />

              <Textarea
                {...form.getInputProps('command')}
                label="Command"
                placeholder="python /app/script.py --query {{query}}"
                description="Command template with {{param}} placeholders"
                minRows={2}
                autosize
                styles={{ input: { fontFamily: '"JetBrains Mono", monospace' } }}
              />
            </Stack>
          </Tabs.Panel>

          <Tabs.Panel value="files" pt="md">
            <Box
              p="md"
              style={{
                backgroundColor: 'var(--app-bg-deep)',
                borderRadius: 'var(--mantine-radius-sm)',
              }}
            >
              <Group justify="space-between" mb="md">
                <Text fz={14} fw={500} c="dimmed">
                  Files to Mount
                </Text>
                <Button size="xs" variant="light" leftSection={<IconPlus size={14} />} onClick={handleAddFile}>
                  Add File
                </Button>
              </Group>

              {visibleFiles.length === 0 ? (
                <Text fz={13} c="dimmed" ta="center" py="md">
                  No files. Add files to mount into the container.
                </Text>
              ) : (
                <Stack gap="md">
                  {files.map(
                    (file, index) =>
                      !file._destroy && (
                        <Box
                          key={index}
                          p="md"
                          style={{
                            backgroundColor: 'var(--app-bg-paper)',
                            border: '1px solid var(--app-border-default)',
                            borderRadius: 'var(--mantine-radius-sm)',
                          }}
                        >
                          <Group justify="space-between" align="flex-start" mb="sm">
                            <TextInput
                              value={file.path}
                              onChange={(e) => handleFileChange(index, 'path', e.currentTarget.value)}
                              label="Path"
                              placeholder="/workspace/script.py"
                              description="Must start with /workspace/"
                              size="sm"
                              style={{ flex: 1 }}
                              styles={{
                                input: { fontFamily: '"JetBrains Mono", monospace' },
                              }}
                              error={
                                file.path && !file.path.startsWith('/workspace/')
                                  ? 'Path must start with /workspace/'
                                  : undefined
                              }
                            />
                            <ActionIcon
                              variant="subtle"
                              color="red"
                              size="sm"
                              mt={28}
                              onClick={() => handleRemoveFile(index)}
                            >
                              <IconTrash size={16} />
                            </ActionIcon>
                          </Group>

                          <SegmentedControl
                            size="xs"
                            mb="sm"
                            value={file.mode}
                            onChange={(val) => handleModeChange(index, val as FileMode)}
                            data={[
                              {
                                value: 'text',
                                label: (
                                  <Group gap={6} wrap="nowrap">
                                    <IconCode size={14} />
                                    <span>Text</span>
                                  </Group>
                                ),
                              },
                              {
                                value: 'upload',
                                label: (
                                  <Group gap={6} wrap="nowrap">
                                    <IconUpload size={14} />
                                    <span>Upload</span>
                                  </Group>
                                ),
                              },
                            ]}
                          />

                          {file.mode === 'text' ? (
                            <ToolFileEditor
                              value={file.content}
                              onChange={(val) => handleFileChange(index, 'content', val)}
                              path={file.path}
                            />
                          ) : (
                            <Box>
                              <input
                                type="file"
                                ref={(el) => {
                                  fileInputRefs.current[index] = el;
                                }}
                                style={{ display: 'none' }}
                                onChange={(e) => {
                                  const selected = e.target.files?.[0] ?? null;
                                  handleFileUpload(index, selected);
                                }}
                              />

                              {file.file ? (
                                <Group
                                  gap="sm"
                                  p="sm"
                                  style={{
                                    border: '1px solid var(--app-border-default)',
                                    borderRadius: 'var(--mantine-radius-sm)',
                                    backgroundColor: 'var(--app-bg-deep)',
                                  }}
                                >
                                  <IconFile size={20} style={{ opacity: 0.6 }} />
                                  <Box style={{ flex: 1 }}>
                                    <Text fz={13} fw={500}>
                                      {file.file.name}
                                    </Text>
                                    <Text fz={11} c="dimmed">
                                      {formatFileSize(file.file.size)}
                                    </Text>
                                  </Box>
                                  <Button
                                    size="xs"
                                    variant="subtle"
                                    onClick={() => fileInputRefs.current[index]?.click()}
                                  >
                                    Replace
                                  </Button>
                                </Group>
                              ) : file.existingFileUrl ? (
                                <Group
                                  gap="sm"
                                  p="sm"
                                  style={{
                                    border: '1px solid var(--app-border-default)',
                                    borderRadius: 'var(--mantine-radius-sm)',
                                    backgroundColor: 'var(--app-bg-deep)',
                                  }}
                                >
                                  <IconFile size={20} style={{ opacity: 0.6 }} />
                                  <Box style={{ flex: 1 }}>
                                    <Text fz={13} fw={500}>
                                      {file.existingFileName || 'Uploaded file'}
                                    </Text>
                                    <Anchor href={file.existingFileUrl} target="_blank" fz={11}>
                                      <Group gap={4}>
                                        <IconDownload size={12} />
                                        Download
                                      </Group>
                                    </Anchor>
                                  </Box>
                                  <Button
                                    size="xs"
                                    variant="subtle"
                                    onClick={() => fileInputRefs.current[index]?.click()}
                                  >
                                    Replace
                                  </Button>
                                </Group>
                              ) : (
                                <Box
                                  p="lg"
                                  ta="center"
                                  style={{
                                    border: '2px dashed var(--app-border-default)',
                                    borderRadius: 'var(--mantine-radius-sm)',
                                    cursor: 'pointer',
                                  }}
                                  onClick={() => fileInputRefs.current[index]?.click()}
                                >
                                  <IconUpload size={28} style={{ opacity: 0.4, marginBottom: 4 }} />
                                  <Text fz={13} c="dimmed">
                                    Click to select a file
                                  </Text>
                                </Box>
                              )}
                            </Box>
                          )}
                        </Box>
                      ),
                  )}
                </Stack>
              )}
            </Box>
          </Tabs.Panel>

          <Tabs.Panel value="config" pt="md">
            <Box
              p="md"
              style={{
                backgroundColor: 'var(--app-bg-deep)',
                borderRadius: 'var(--mantine-radius-sm)',
              }}
            >
              <Text fz={14} c="dimmed" mb="md">
                Select secrets to inject as environment variables
              </Text>
              <MultiSelect
                data={configItemNames}
                value={form.values.requiredConfigItems}
                onChange={(val) => form.setFieldValue('requiredConfigItems', val)}
                placeholder="Select secrets..."
                searchable
                clearable
                description="These will be injected as environment variables into the container"
              />
            </Box>
          </Tabs.Panel>
        </Tabs>

        <Group justify="flex-end" mt="md">
          <Button variant="default" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button type="submit" loading={submitting}>
            {isEditMode ? 'Save' : 'Create'}
          </Button>
        </Group>
      </form>
    </Modal>
  );
};
