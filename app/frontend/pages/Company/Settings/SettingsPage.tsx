import type { FormDataConvertible } from '@inertiajs/core';
import { Head, router, usePage } from '@inertiajs/react';
import {
  Box,
  Button,
  Card,
  ColorInput,
  Divider,
  FileInput,
  Group,
  Image,
  NumberInput,
  Stack,
  Text,
  TextInput,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { IconAdjustments, IconLock, IconPalette, IconUpload } from '@tabler/icons-react';
import { zod4Resolver as zodResolver } from 'mantine-form-zod-resolver';
import { useState } from 'react';
import { z } from 'zod';

import { AuthLayout } from 'layouts/AuthLayout';

import { SettingsTabs } from './SettingsTabs';

const schema = z.object({
  displayName: z.string().max(100).optional(),
  primaryColor: z.string().max(32).optional(),
  secondaryColor: z.string().max(32).optional(),
  logo: z.instanceof(File).nullable(),
  removeLogo: z.boolean(),
  // Empty means no limit at all, which is also unbilled. The arithmetic behind a
  // number is the server's to judge.
  capacity: z
    .string()
    .optional()
    .refine((v) => !v || /^[1-9]\d*$/.test(v), 'Must be a whole number greater than zero'),
});

interface CompanyProps {
  name: string;
  displayName: string | null;
  logoUrl: string | null;
  primaryColor: string;
  secondaryColor: string;
}

interface CapacityAllocation {
  name: string;
  maxSessions: number;
}

interface Capacity {
  /** What the company may run at once, or null when it has no limit. */
  maxSessions: number | null;
  /** What is left after its projects' reservations; null when there is no limit. */
  available: number | null;
  reserved: number;
  allocations: CapacityAllocation[];
  projectDefault: number;
  /** False in the hosted product: the number we invoice for is not self-serve. */
  canManage: boolean;
}

interface Props {
  company: CompanyProps;
  capacity: Capacity;
  canManage: boolean;
}

const SettingsPage = () => {
  const { company, capacity, canManage } = usePage<{ props: Props }>().props as unknown as Props;
  const pageErrors = (usePage().props as unknown as { errors?: Record<string, string> }).errors;

  const form = useForm({
    initialValues: {
      displayName: company.displayName || '',
      primaryColor: company.primaryColor,
      secondaryColor: company.secondaryColor,
      logo: null as File | null,
      removeLogo: false,
      capacity: capacity.maxSessions != null ? String(capacity.maxSessions) : '',
    },
    validate: zodResolver(schema),
  });

  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = (values: typeof form.values) => {
    setIsSubmitting(true);

    const callbacks = {
      preserveScroll: true,
      onSuccess: () => {
        setIsSubmitting(false);
        form.setFieldValue('logo', null);
        form.setFieldValue('removeLogo', false);
        form.resetDirty();
        notifications.show({ message: 'Company settings saved', color: 'green' });
      },
      onError: () => {
        setIsSubmitting(false);
        notifications.show({ message: 'Failed to save settings', color: 'red' });
      },
    };

    const payload: Record<string, FormDataConvertible> = {
      company: {
        displayName: values.displayName.trim(),
        primaryColor: values.primaryColor,
        secondaryColor: values.secondaryColor,
        removeLogo: values.removeLogo,
      },
      // Sent only when this person may set it: the key's presence is what tells
      // the server a limit was submitted at all, and an empty one clears it.
      ...(capacity.canManage ? { capacity: values.capacity.trim() } : {}),
    } as Record<string, FormDataConvertible>;

    // A File cannot travel as JSON, so a chosen logo turns the whole save into a
    // multipart POST that Rails reads as the PATCH it is.
    if (values.logo) {
      const fd = new FormData();
      fd.append('_method', 'PATCH');
      fd.append('company[logo]', values.logo);
      Object.entries(payload.company as Record<string, FormDataConvertible>).forEach(([key, value]) => {
        fd.append(`company[${key}]`, String(value));
      });
      if (capacity.canManage) fd.append('capacity', values.capacity.trim());
      router.post('/company/settings', fd, { ...callbacks, forceFormData: true });
      return;
    }

    router.patch('/company/settings', payload, callbacks);
  };

  return (
    <AuthLayout>
      <Head title={`Settings — ${company.name}`} />
      <SettingsTabs active="general" companyName={company.name}>
        <form onSubmit={form.onSubmit(handleSubmit)}>
          <Stack gap="lg" maw={720}>
            <Card withBorder padding="lg">
              <Group gap="xs" mb="md">
                <IconPalette size={18} />
                <Text fw={600}>Branding</Text>
              </Group>
              <Stack gap="md">
                <TextInput
                  label="Display name"
                  description={`Shown in place of “${company.name}” across the workspace. Leave empty to use the legal name.`}
                  placeholder={company.name}
                  disabled={!canManage}
                  {...form.getInputProps('displayName')}
                />
                <Group grow align="flex-start">
                  <ColorInput label="Primary color" disabled={!canManage} {...form.getInputProps('primaryColor')} />
                  <ColorInput label="Secondary color" disabled={!canManage} {...form.getInputProps('secondaryColor')} />
                </Group>
                <Box>
                  <Text fz="sm" fw={500} mb={6}>
                    Logo
                  </Text>
                  <Group align="center" gap="md">
                    {company.logoUrl && !form.values.removeLogo ? (
                      <Image src={company.logoUrl} alt={company.name} h={44} w="auto" fit="contain" />
                    ) : (
                      <Text fz="sm" c="dimmed">
                        None
                      </Text>
                    )}
                    {company.logoUrl && canManage && (
                      <Button
                        variant="subtle"
                        size="compact-sm"
                        color="red"
                        onClick={() => {
                          form.setFieldValue('removeLogo', !form.values.removeLogo);
                          form.setFieldValue('logo', null);
                        }}
                      >
                        {form.values.removeLogo ? 'Keep logo' : 'Remove logo'}
                      </Button>
                    )}
                  </Group>
                  <FileInput
                    mt="sm"
                    label="Replace logo"
                    description="PNG, JPEG, GIF, WebP or SVG, up to 5 MB."
                    placeholder="Choose a file"
                    accept="image/png,image/jpeg,image/gif,image/webp,image/svg+xml"
                    clearable
                    disabled={!canManage}
                    leftSection={<IconUpload size={16} />}
                    error={pageErrors?.logo}
                    value={form.values.logo}
                    onChange={(file) => {
                      form.setFieldValue('logo', file);
                      if (file) form.setFieldValue('removeLogo', false);
                    }}
                  />
                </Box>
              </Stack>
            </Card>

            <Card withBorder padding="lg">
              <Group gap="xs" mb="md">
                <IconAdjustments size={18} />
                <Text fw={600}>Workers</Text>
              </Group>
              <Stack gap="md">
                {capacity.canManage ? (
                  <NumberInput
                    label="Workers"
                    description={`How many sessions this company may run at once — each worker runs one. Projects reserve workers out of it; those without a reservation share what is left, up to ${capacity.projectDefault} each. Leave empty for no limit.`}
                    placeholder="No limit"
                    min={1}
                    allowDecimal={false}
                    allowNegative={false}
                    value={form.values.capacity}
                    error={form.errors.capacity || pageErrors?.capacity}
                    onChange={(v) => {
                      form.setFieldValue('capacity', v === '' || v == null ? '' : String(v));
                    }}
                  />
                ) : (
                  <Box>
                    <Text fz="sm" fw={500}>
                      Workers
                    </Text>
                    <Group gap={6} mt={4}>
                      <Text fz="xl" fw={600}>
                        {capacity.maxSessions ?? 'No limit'}
                      </Text>
                      <IconLock size={14} />
                      <Text fz="xs" c="dimmed">
                        contact us to change this
                      </Text>
                    </Group>
                  </Box>
                )}

                {capacity.maxSessions != null && (
                  <Box>
                    <Divider mb="xs" />
                    <Text fz="xs" c="dimmed">
                      {capacity.reserved} of {capacity.maxSessions} is reserved by projects, leaving{' '}
                      {capacity.available} shared by every project that has no reservation of its own.
                    </Text>
                    {capacity.allocations.length > 0 && (
                      <Text fz="xs" c="dimmed" mt={4}>
                        Reserved: {capacity.allocations.map((a) => `${a.name} ${a.maxSessions}`).join(', ')}
                      </Text>
                    )}
                  </Box>
                )}
              </Stack>
            </Card>

            {canManage && (
              <Group justify="flex-end">
                <Button type="submit" loading={isSubmitting} disabled={!form.isDirty()}>
                  Save Changes
                </Button>
              </Group>
            )}
          </Stack>
        </form>
      </SettingsTabs>
    </AuthLayout>
  );
};

export default SettingsPage;
