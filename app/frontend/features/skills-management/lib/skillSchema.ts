import { z } from 'zod';

export const skillSchema = z.object({
  name: z
    .string()
    .min(1, 'Name is required')
    .max(100, 'Name must be at most 100 characters')
    .regex(
      /^[a-z][a-z0-9_-]*$/,
      'Name must start with letter, use only lowercase letters, numbers, underscores, hyphens',
    ),
  title: z.string().min(1, 'Title is required').max(200, 'Title must be at most 200 characters'),
  content: z.string().min(1, 'Content is required').max(50000, 'Content must be at most 50000 characters'),
  description: z.string().max(1000, 'Description must be at most 1000 characters').optional(),
});

export type SkillFormData = z.infer<typeof skillSchema>;
