import { z } from 'zod';

export const workflowSchema = z.object({
  name: z.string().min(1, 'Name is required').max(200, 'Name must be at most 200 characters'),
  description: z.string().max(2000, 'Description must be at most 2000 characters').optional(),
});

export type WorkflowFormData = z.infer<typeof workflowSchema>;
