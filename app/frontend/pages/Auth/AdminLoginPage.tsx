import { Head, useForm } from '@inertiajs/react';
import { Button, Center, Paper, PasswordInput, Stack, Text, TextInput, Title } from '@mantine/core';
import { useState } from 'react';
import { z } from 'zod';

import { adminLoginPath } from 'shared/routes';
import { BrandLockup, PageShell } from 'shared/ui';

import classes from './LoginPage.module.css';

const schema = z.object({
  email: z.string().min(1, 'Email is required').email('Invalid email format'),
  password: z.string().min(1, 'Password is required'),
});

const AdminLoginPage = () => {
  const { data, setData, post, processing, errors } = useForm({ email: '', password: '' });
  const [clientErrors, setClientErrors] = useState<Partial<Record<'email' | 'password', string>>>({});

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const result = schema.safeParse({ email: data.email.trim(), password: data.password });
    if (!result.success) {
      const next: typeof clientErrors = {};
      for (const issue of result.error.issues) {
        const field = issue.path[0] as 'email' | 'password';
        next[field] ??= issue.message;
      }
      setClientErrors(next);
      return;
    }
    setClientErrors({});
    post(adminLoginPath());
  };

  return (
    <PageShell variant="centered">
      <Head title="Administrator sign in — Aixle Flow" />
      <Paper className={classes.formCard} p="xl" radius="md" w="100%" maw={420} shadow="0 8px 32px rgba(0, 0, 0, 0.4)">
        <Center mb={32}>
          <BrandLockup />
        </Center>
        <Title order={3} ta="center" mb="lg">
          Administrator sign in
        </Title>
        <form onSubmit={handleSubmit}>
          <Stack gap="md">
            <TextInput
              label="Email"
              value={data.email}
              onChange={(e) => setData('email', e.currentTarget.value)}
              error={clientErrors.email || errors.email}
              autoComplete="username"
              autoFocus
              classNames={{ input: classes.input, label: classes.label }}
            />
            <PasswordInput
              label="Password"
              value={data.password}
              onChange={(e) => setData('password', e.currentTarget.value)}
              error={clientErrors.password || errors.password}
              autoComplete="current-password"
              classNames={{ input: classes.input, label: classes.label, visibilityToggle: classes.visibilityToggle }}
              visibilityToggleButtonProps={{ 'aria-label': 'Toggle password visibility' }}
            />
            <Button type="submit" fullWidth size="lg" loading={processing} classNames={{ root: classes.submitButton }}>
              Sign in
            </Button>
          </Stack>
        </form>
        <Text ta="center" size="xs" c="dimmed" mt="lg" className={classes.subtitle}>
          Platform operator accounts only.
        </Text>
      </Paper>
    </PageShell>
  );
};

export default AdminLoginPage;
