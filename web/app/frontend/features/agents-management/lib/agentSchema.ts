import { z } from 'zod';

export const agentSchema = z.object({
  name: z
    .string()
    .min(1, 'Name is required')
    .max(100, 'Name must be at most 100 characters')
    .regex(/^[a-z][a-z0-9_]*$/, 'Name must start with letter, use only lowercase letters, numbers, underscores'),
  title: z.string().min(1, 'Title is required').max(200, 'Title must be at most 200 characters'),
  icon: z.string().max(10, 'Icon must be at most 10 characters').optional(),
  persona: z.string().min(1, 'Persona is required').max(5000, 'Persona must be at most 5000 characters'),
  communicationStyle: z.string().max(2000, 'Communication style must be at most 2000 characters').optional(),
  principles: z.string().max(2000, 'Principles must be at most 2000 characters').optional(),
});

export type AgentFormData = z.infer<typeof agentSchema>;
