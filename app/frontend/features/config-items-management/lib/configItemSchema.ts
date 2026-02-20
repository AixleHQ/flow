import { z } from 'zod';

export const configItemSchema = z.object({
  name: z
    .string()
    .min(1, 'Name is required')
    .max(255, 'Name must be at most 255 characters')
    .regex(/^[A-Z0-9_]+$/, 'Name must contain only uppercase letters, numbers, and underscores'),
  value: z.string().min(1, 'Value is required'),
  description: z.string().max(1000, 'Description must be at most 1000 characters').optional(),
  itemType: z.enum(['secret', 'variable']),
});

export type ConfigItemFormData = z.infer<typeof configItemSchema>;
