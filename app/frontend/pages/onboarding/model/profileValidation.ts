import { z } from 'zod';

export const POSITION_VALUES = ['dev', 'qa', 'pm_po_ba', 'designer', 'cto'] as const;
export const LANGUAGE_VALUES = ['en', 'ru', 'es', 'de', 'fr', 'ja', 'zh'] as const;

// Include empty string for placeholder state
const POSITION_WITH_EMPTY = ['', 'dev', 'qa', 'pm_po_ba', 'designer', 'cto'] as const;
const LANGUAGE_WITH_EMPTY = ['', 'en', 'ru', 'es', 'de', 'fr', 'ja', 'zh'] as const;

// Allow empty string as valid value in form (for placeholder state)
export const profileSchema = z.object({
  position: z.enum(POSITION_WITH_EMPTY),
  preferredAgentLanguage: z.enum(LANGUAGE_WITH_EMPTY),
});

export type ProfileFormData = z.infer<typeof profileSchema>;
