import { z } from 'zod';

export const POSITION_VALUES = ['dev', 'qa', 'pm_po_ba', 'designer', 'cto'] as const;
export const LANGUAGE_VALUES = ['en', 'ru', 'es', 'de', 'fr', 'ja', 'zh'] as const;

export const profileSchema = z.object({
  position: z.enum(POSITION_VALUES, {
    required_error: 'Position is required',
    invalid_type_error: 'Please select a valid position',
  }),
  preferredAgentLanguage: z.enum(LANGUAGE_VALUES, {
    required_error: 'Preferred language is required',
    invalid_type_error: 'Please select a valid language',
  }),
});

export type ProfileFormData = z.infer<typeof profileSchema>;
