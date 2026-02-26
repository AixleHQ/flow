import { z } from 'zod';

export const toolFileSchema = z
  .object({
    id: z.number().optional(),
    path: z
      .string()
      .min(1, 'Path is required')
      .regex(/^\/workspace\//, 'Path must start with /workspace/'),
    content: z.string(),
    file: z.instanceof(File).optional(),
    existingFileUrl: z.string().optional(),
    existingFileName: z.string().optional(),
    _destroy: z.boolean().optional(),
  })
  .refine((data) => data._destroy || data.content || data.file || data.existingFileUrl, {
    message: 'Either text content or an uploaded file is required',
    path: ['content'],
  });

export const toolSchema = z.object({
  name: z
    .string()
    .min(1, 'Name is required')
    .max(100, 'Name must be at most 100 characters')
    .regex(/^[a-z][a-z0-9_]*$/, 'Name must start with letter, use only lowercase letters, numbers, underscores'),
  displayName: z.string().min(1, 'Display name is required').max(200, 'Display name must be at most 200 characters'),
  description: z.string().max(2000, 'Description must be at most 2000 characters').optional(),
  dockerImage: z.string().min(1, 'Docker image is required'),
  command: z.string().max(2000, 'Command must be at most 2000 characters').optional(),
  requiredConfigItems: z.array(z.string()).optional(),
  inputSchema: z.record(z.unknown()).optional(),
  toolFilesAttributes: z.array(toolFileSchema).optional(),
});

export type ToolFormData = z.infer<typeof toolSchema>;
