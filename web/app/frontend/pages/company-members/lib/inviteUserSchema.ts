import { z } from 'zod';

export const inviteUserSchema = z.object({
  email: z.string().email('Please enter a valid email address'),
  name: z.string().min(1, 'Name is required').max(100, 'Name is too long'),
  role: z.enum(['employee', 'admin']),
});

export type InviteUserFormData = z.infer<typeof inviteUserSchema>;
