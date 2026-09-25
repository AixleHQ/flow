import type { Member } from '@/types/generated';
import { AuthLayout } from 'layouts/AuthLayout';

import { MembersContent } from 'shared/resources/members/MembersContent';

interface Props {
  users: Member[];
}

function MembersIndex({ users }: Props) {
  return (
    <AuthLayout>
      <MembersContent
        users={users}
        basePath="/company/members"
        title="Company Members"
        subtitle="People with access to this company workspace. Admins manage members, integrations, and settings; employees and viewers work within projects."
      />
    </AuthLayout>
  );
}

export default MembersIndex;
