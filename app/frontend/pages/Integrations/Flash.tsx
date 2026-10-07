import { usePage } from '@inertiajs/react';
import { Alert } from '@mantine/core';

export const Flash = () => {
  const { flash } = usePage<{ flash?: Record<string, unknown> }>().props;
  return (
    <>
      {typeof flash?.alert === 'string' && (
        <Alert color="red" variant="light">
          {flash.alert}
        </Alert>
      )}
      {typeof flash?.notice === 'string' && (
        <Alert color="green" variant="light">
          {flash.notice}
        </Alert>
      )}
    </>
  );
};
