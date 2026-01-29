import { z } from 'zod';

export const profileSchema = z.object({
  name: z
    .string()
    .min(2, 'Name must be at least 2 characters')
    .max(100, 'Name must be less than 100 characters')
    .trim(),
});

export type IProfileFormData = z.infer<typeof profileSchema>;
