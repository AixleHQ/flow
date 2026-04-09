import { Center, Container } from '@mantine/core';

interface IGuestLayoutProps {
  children: React.ReactNode;
}

export const GuestLayout = ({ children }: IGuestLayoutProps) => (
  <Center mih="100vh">
    <Container size="xs" w="100%">
      {children}
    </Container>
  </Center>
);
