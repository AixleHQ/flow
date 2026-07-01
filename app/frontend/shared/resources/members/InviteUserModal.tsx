import { router } from '@inertiajs/react';
import { Button, Group, Modal, Select, Stack, TextInput } from '@mantine/core';
import { useForm } from '@mantine/form';
import { zod4Resolver as zodResolver } from 'mantine-form-zod-resolver';
import { useEffect, useState, type FC } from 'react';
import { z } from 'zod';

const schema = z.object({
  email: z.string().email('Invalid email').min(1, 'Email is required'),
  name: z.string().min(1, 'Name is required'),
  role: z.string().min(1, 'Role is required'),
});

type FormData = z.infer<typeof schema>;

interface Props {
  opened: boolean;
  onClose: () => void;
  basePath: string;
}

const ROLE_OPTIONS = [
  { value: 'employee', label: 'Employee' },
  { value: 'admin', label: 'Admin' },
  { value: 'viewer', label: 'Viewer' },
];

export const InviteUserModal: FC<Props> = ({ opened, onClose, basePath }) => {
  const [loading, setLoading] = useState(false);

  const form = useForm<FormData>({
    validate: zodResolver(schema),
    initialValues: {
      email: '',
      name: '',
      role: 'employee',
    },
  });

  useEffect(() => {
    if (opened) {
      form.reset();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened]);

  const handleSubmit = (values: FormData) => {
    setLoading(true);

    router.post(
      basePath,
      { user: values },
      {
        preserveScroll: true,
        onFinish: () => setLoading(false),
        onSuccess: () => onClose(),
      },
    );
  };

  return (
    <Modal opened={opened} onClose={onClose} title="Invite Member" centered>
      <form onSubmit={form.onSubmit(handleSubmit)}>
        <Stack gap="md">
          <TextInput label="Email" placeholder="user@company.com" {...form.getInputProps('email')} required />
          <TextInput label="Full Name" placeholder="John Doe" {...form.getInputProps('name')} required />
          <Select label="Role" data={ROLE_OPTIONS} {...form.getInputProps('role')} />
          <Group justify="flex-end" mt="sm">
            <Button variant="default" onClick={onClose} disabled={loading}>
              Cancel
            </Button>
            <Button type="submit" loading={loading}>
              Send Invitation
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
};
