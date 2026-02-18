import { z } from 'zod';

export const uploadAssetSchema = z.object({
  name: z.string().min(1, 'Name is required').max(255, 'Name must be at most 255 characters'),
  folder: z
    .string()
    .regex(/^[a-z0-9_-]*$/, 'Only lowercase letters, numbers, hyphens, underscores')
    .max(100)
    .optional()
    .or(z.literal('')),
});

export type UploadAssetFormData = z.infer<typeof uploadAssetSchema>;

export const editAssetSchema = z.object({
  folder: z
    .string()
    .regex(/^[a-z0-9_-]*$/, 'Only lowercase letters, numbers, hyphens, underscores')
    .max(100)
    .optional()
    .or(z.literal('')),
  tags: z.string().max(500).optional(),
  public: z.boolean(),
});

export type EditAssetFormData = z.infer<typeof editAssetSchema>;
