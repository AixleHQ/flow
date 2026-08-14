import { router } from '@inertiajs/react';
import { Button, Select, Stack, TextInput } from '@mantine/core';
import { useForm } from '@mantine/form';
import { IconSend } from '@tabler/icons-react';
import { zod4Resolver as zodResolver } from 'mantine-form-zod-resolver';
import { useEffect, useState, type FC } from 'react';
import { z } from 'zod';

import { ResourceDrawer } from 'shared/ui/ResourceDrawer';

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

export const InviteMemberDrawer: FC<Props> = ({ opened, onClose, basePath }) => {
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

  const handleClose = () => {
    form.reset();
    onClose();
  };

  const handleSubmit = (values: FormData) => {
    setLoading(true);

    router.post(
      basePath,
      { user: values },
      {
        preserveScroll: true,
        onFinish: () => setLoading(false),
        onSuccess: () => handleClose(),
      },
    );
  };

  return (
    <ResourceDrawer
      opened={opened}
      onClose={handleClose}
      title="Invite Member"
      footer={
        <Button
          type="submit"
          form="invite-member-form"
          fullWidth
          leftSection={<IconSend size={16} />}
          loading={loading}
        >
          Send Invite
        </Button>
      }
    >
      <form id="invite-member-form" onSubmit={form.onSubmit(handleSubmit)}>
        <Stack gap="md">
          <TextInput
            label="Email"
            description="They'll receive an invitation link to join the workspace"
            placeholder="name@company.com"
            withAsterisk
            {...form.getInputProps('email')}
          />
          <TextInput label="Full Name" placeholder="Jane Doe" withAsterisk {...form.getInputProps('name')} />
          <Select
            label="Role"
            description="Admins can manage members and company settings"
            data={ROLE_OPTIONS}
            {...form.getInputProps('role')}
          />
        </Stack>
      </form>
    </ResourceDrawer>
  );
};
