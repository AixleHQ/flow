import { z } from 'zod';

export const subStepSchema = z.object({
  id: z.number().optional(),
  name: z.string().min(1, 'Name is required'),
  position: z.number(),
  description: z.string().optional(),
  instructions: z.string().optional(),
  required: z.boolean().default(true),
  _destroy: z.boolean().optional(),
});

export const stepSchema = z.object({
  name: z.string().min(1, 'Name is required').max(200),
  description: z.string().max(2000).default(''),
  instructions: z.string().default(''),
  agentId: z.number().nullable().optional(),
  allowNonInteractive: z.boolean().default(false),
  skipPolicy: z.enum(['never', 'if_outputs_exist', 'manual']).default('never'),
  onFailure: z.enum(['retry', 'skip', 'fail']).default('fail'),
  maxRetries: z.number().min(0).max(10).default(0),
  preferredModel: z
    .string()
    .regex(/^[a-z0-9][a-z0-9._:-]*$/, 'Invalid model ID format')
    .nullable()
    .optional(),
  subStepsAttributes: z.array(subStepSchema).optional(),
});

export type StepFormData = z.output<typeof stepSchema>;
export type SubStepFormData = z.infer<typeof subStepSchema>;
