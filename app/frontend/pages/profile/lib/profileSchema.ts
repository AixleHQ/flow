import { z } from 'zod';

import { AGENT_LANGUAGES } from 'entities/user';

export const profileSchema = z.object({
  name: z
    .string()
    .min(2, 'Name must be at least 2 characters')
    .max(100, 'Name must be less than 100 characters')
    .trim(),
  preferredAgentLanguage: z.enum(AGENT_LANGUAGES),
});

export type IProfileFormData = z.infer<typeof profileSchema>;
