export const AGENT_LANGUAGES = ['en', 'ru', 'es', 'de', 'fr', 'ja', 'zh', 'pt', 'it', 'pl', 'uk'] as const;

export type AgentLanguage = (typeof AGENT_LANGUAGES)[number];

export interface ILanguageOption {
  value: AgentLanguage;
  label: string;
}

export const LANGUAGE_OPTIONS: ILanguageOption[] = [
  { value: 'en', label: 'English' },
  { value: 'ru', label: 'Russian' },
  { value: 'es', label: 'Spanish' },
  { value: 'de', label: 'German' },
  { value: 'fr', label: 'French' },
  { value: 'ja', label: 'Japanese' },
  { value: 'zh', label: 'Chinese' },
  { value: 'pt', label: 'Portuguese' },
  { value: 'it', label: 'Italian' },
  { value: 'pl', label: 'Polish' },
  { value: 'uk', label: 'Ukrainian' },
];
