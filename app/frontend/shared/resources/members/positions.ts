import {
  IconBriefcase,
  IconBrush,
  IconCalculator,
  IconClipboardList,
  IconCode,
  IconDots,
  IconSettings,
  IconSpeakerphone,
  IconTestPipe,
} from '@tabler/icons-react';

import type { Member } from '@/types/generated';

export type MemberPosition = NonNullable<Member['position']>;

export const POSITION_OPTIONS: { value: MemberPosition; label: string; icon: typeof IconCode }[] = [
  { value: 'engineering', label: 'Engineering', icon: IconCode },
  { value: 'product', label: 'Product Management', icon: IconClipboardList },
  { value: 'design', label: 'Design', icon: IconBrush },
  { value: 'qa', label: 'QA', icon: IconTestPipe },
  { value: 'marketing', label: 'Marketing', icon: IconSpeakerphone },
  { value: 'operations', label: 'Operations', icon: IconSettings },
  { value: 'finance', label: 'Finance / Accounting', icon: IconCalculator },
  { value: 'executive', label: 'Executive Leadership', icon: IconBriefcase },
  { value: 'other', label: 'Other', icon: IconDots },
];

export function positionLabel(position: MemberPosition): string {
  return POSITION_OPTIONS.find((option) => option.value === position)?.label ?? position;
}
