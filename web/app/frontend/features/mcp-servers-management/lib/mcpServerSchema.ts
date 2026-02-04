import { z } from 'zod';

export const mcpServerSchema = z.object({
  name: z
    .string()
    .min(1, 'Name is required')
    .regex(/^[a-z][a-z0-9_-]*$/, 'Must start with letter, use lowercase letters, numbers, dashes, underscores'),
  displayName: z.string().min(1, 'Display name is required'),
  url: z.string().url('Must be a valid URL'),
  transport: z.enum(['sse', 'stdio']).default('sse'),
  headers: z.record(z.string()).default({}),
  description: z.string().optional(),
  enabled: z.boolean().default(true),
});

// Use z.input to get the input type (before defaults are applied)
export type McpServerFormData = z.input<typeof mcpServerSchema>;
