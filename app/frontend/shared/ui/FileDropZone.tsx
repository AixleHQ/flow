import { Box, Text } from '@mantine/core';
import { IconUpload } from '@tabler/icons-react';
import { useRef } from 'react';

interface FileDropZoneProps {
  onFiles: (files: File[]) => void;
  hint: string;
  disabled?: boolean;
}

export function FileDropZone({ onFiles, hint, disabled = false }: FileDropZoneProps) {
  const inputRef = useRef<HTMLInputElement>(null);

  return (
    <>
      <Box
        p="xl"
        ta="center"
        style={{
          border: '2px dashed var(--app-border-default)',
          borderRadius: 'var(--mantine-radius-md)',
          cursor: disabled ? 'not-allowed' : 'pointer',
          opacity: disabled ? 0.6 : 1,
          transition: 'border-color 150ms',
        }}
        onClick={() => {
          if (!disabled) inputRef.current?.click();
        }}
        onDragOver={(e: React.DragEvent) => {
          e.preventDefault();
          e.stopPropagation();
        }}
        onDrop={(e: React.DragEvent) => {
          e.preventDefault();
          e.stopPropagation();
          if (disabled) return;
          const files = Array.from(e.dataTransfer.files ?? []);
          if (files.length > 0) onFiles(files);
        }}
      >
        <IconUpload size={32} color="var(--mantine-color-dimmed)" />
        <Text fz={14} c="dimmed" mt="sm">
          Click to select files or drag &amp; drop
        </Text>
        <Text fz={12} c="dimmed">
          {hint}
        </Text>
      </Box>
      <input
        ref={inputRef}
        type="file"
        multiple
        aria-label="Select files"
        style={{ display: 'none' }}
        disabled={disabled}
        onChange={(e) => {
          const files = Array.from(e.target.files ?? []);
          e.target.value = '';
          if (files.length > 0) onFiles(files);
        }}
      />
    </>
  );
}
