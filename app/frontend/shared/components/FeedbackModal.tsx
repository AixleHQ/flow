import { useForm } from '@inertiajs/react';
import {
  Alert,
  Button,
  CloseButton,
  Group,
  Modal,
  Progress,
  SegmentedControl,
  Stack,
  Text,
  Textarea,
} from '@mantine/core';
import { IconPaperclip } from '@tabler/icons-react';
import { useRef, useState } from 'react';

import { formatFileSize } from 'shared/lib/formatFileSize';
import { useConfirmClose } from 'shared/lib/hooks/useConfirmClose';
import { pastedImages } from 'shared/lib/imagePaste';

type FeedbackKind = 'bug' | 'feature_request' | 'support';

const KINDS: { value: FeedbackKind; label: string; placeholder: string }[] = [
  { value: 'bug', label: 'Bug', placeholder: 'What happened, and what did you expect instead?' },
  { value: 'feature_request', label: 'Feature request', placeholder: 'What should we add or change?' },
  { value: 'support', label: 'Support', placeholder: 'What do you need help with?' },
];

// FeedbackSubmission::MESSAGE_MAX, ::ATTACHMENTS_MAX and FeedbackAttachment::MAX_SIZE
const MESSAGE_MAX = 5000;
const ATTACHMENTS_MAX = 5;
const ATTACHMENT_MAX_MB = 20;
const ATTACHMENT_MAX_BYTES = ATTACHMENT_MAX_MB * 1024 * 1024;

const BLANK_FEEDBACK: { kind: FeedbackKind; message: string; attachments: File[] } = {
  kind: 'bug',
  message: '',
  attachments: [],
};

interface FeedbackModalProps {
  opened: boolean;
  onClose: () => void;
}

export const FeedbackModal = ({ opened, onClose }: FeedbackModalProps) => {
  const { data, setData, post, processing, progress, errors, reset, clearErrors, transform } = useForm(BLANK_FEEDBACK);
  const [fileNotice, setFileNotice] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const formError = (errors as Partial<Record<string, string>>).base ?? errors.kind;
  const placeholder = KINDS.find((kind) => kind.value === data.kind)?.placeholder;

  const addFiles = (files: File[]) => {
    const tooLarge = files.filter((file) => file.size > ATTACHMENT_MAX_BYTES);
    const room = ATTACHMENTS_MAX - data.attachments.length;
    const accepted = files.filter((file) => file.size <= ATTACHMENT_MAX_BYTES);

    if (tooLarge.length > 0) {
      setFileNotice(`${tooLarge.map((file) => file.name).join(', ')}: larger than ${ATTACHMENT_MAX_MB} MB.`);
    } else if (accepted.length > room) {
      setFileNotice(`Attach at most ${ATTACHMENTS_MAX} files.`);
    } else {
      setFileNotice(null);
    }
    if (accepted.length > 0 && room > 0) setData('attachments', [...data.attachments, ...accepted.slice(0, room)]);
  };

  const removeFile = (index: number) => {
    setData(
      'attachments',
      data.attachments.filter((_, i) => i !== index),
    );
    setFileNotice(null);
  };

  const handleClose = () => {
    reset();
    clearErrors();
    setFileNotice(null);
    onClose();
  };
  const requestClose = useConfirmClose(data.message.trim() !== '' || data.attachments.length > 0, handleClose);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    transform((d) => ({ feedback: { ...d, page_url: window.location.href } }));
    post('/company/feedback', {
      preserveScroll: true,
      // A refused message comes back to this page: keep the dialog open with what was typed.
      preserveState: true,
      onSuccess: handleClose,
    });
  };

  return (
    <Modal opened={opened} onClose={requestClose} title="Send feedback" size="lg">
      <form onSubmit={handleSubmit}>
        <Stack gap="md">
          {formError && <Alert color="red">{formError}</Alert>}
          <SegmentedControl
            fullWidth
            value={data.kind}
            onChange={(value) => setData('kind', value as FeedbackKind)}
            disabled={processing}
            data={KINDS.map(({ value, label }) => ({ value, label }))}
          />
          <Textarea
            label="Message"
            description="Paste a screenshot here to attach it."
            placeholder={placeholder}
            value={data.message}
            onChange={(e) => setData('message', e.currentTarget.value)}
            onPaste={(e) => {
              const images = pastedImages(e.clipboardData);
              if (images.length > 0) addFiles(images);
            }}
            required
            disabled={processing}
            maxLength={MESSAGE_MAX}
            autosize
            minRows={5}
            maxRows={14}
            error={errors.message}
            data-autofocus
          />
          <Stack gap={6}>
            {data.attachments.map((file, index) => (
              <Group key={`${file.name}-${index}`} gap="xs" wrap="nowrap">
                <IconPaperclip size={14} />
                <Text size="sm" truncate style={{ flex: 1 }}>
                  {file.name}
                </Text>
                <Text size="xs" c="dimmed">
                  {formatFileSize(file.size)}
                </Text>
                <CloseButton
                  size="sm"
                  aria-label={`Remove ${file.name}`}
                  onClick={() => removeFile(index)}
                  disabled={processing}
                />
              </Group>
            ))}
            {fileNotice && (
              <Text size="xs" c="red">
                {fileNotice}
              </Text>
            )}
            <input
              ref={fileInputRef}
              type="file"
              multiple
              hidden
              aria-label="Attach files"
              onChange={(e) => {
                addFiles(Array.from(e.currentTarget.files ?? []));
                e.currentTarget.value = '';
              }}
            />
            <Group>
              <Button
                variant="default"
                size="xs"
                leftSection={<IconPaperclip size={14} />}
                onClick={() => fileInputRef.current?.click()}
                disabled={processing || data.attachments.length >= ATTACHMENTS_MAX}
              >
                Attach files
              </Button>
              <Text size="xs" c="dimmed">
                Up to {ATTACHMENTS_MAX} files, {ATTACHMENT_MAX_MB} MB each.
              </Text>
            </Group>
          </Stack>
          {processing && progress && <Progress value={progress.percentage ?? 0} size="sm" />}
          <Text size="xs" c="dimmed">
            Your name, email and the address of this page are sent along with your message.
          </Text>
          <Group justify="flex-end">
            <Button variant="subtle" onClick={requestClose} disabled={processing}>
              Cancel
            </Button>
            <Button type="submit" loading={processing} disabled={!data.message.trim()}>
              Send
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
};
