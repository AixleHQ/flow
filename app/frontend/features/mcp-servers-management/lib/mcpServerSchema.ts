import { z } from 'zod';

const transportEnum = z.enum(['http', 'sse', 'stdio']).default('http');

export const mcpServerSchema = z
  .object({
    name: z
      .string()
      .min(1, 'Name is required')
      .regex(/^[a-z][a-z0-9_-]*$/, 'Must start with letter, use lowercase letters, numbers, dashes, underscores'),
    displayName: z.string().min(1, 'Display name is required'),
    transport: transportEnum,
    url: z.string().optional().default(''),
    headers: z.record(z.string()).default({}),
    command: z.string().optional().default(''),
    env: z.record(z.string()).default({}),
    description: z.string().optional(),
    enabled: z.boolean().default(true),
  })
  .superRefine((data, ctx) => {
    if (data.transport === 'stdio') {
      if (!data.command || data.command.trim() === '') {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: 'Command is required for stdio transport',
          path: ['command'],
        });
      }
    } else {
      if (!data.url || data.url.trim() === '') {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: 'URL is required',
          path: ['url'],
        });
      } else {
        try {
          new URL(data.url);
        } catch {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: 'Must be a valid URL',
            path: ['url'],
          });
        }
      }
    }
  });

export type McpServerFormData = z.input<typeof mcpServerSchema>;
