import type { Member } from '@/types/generated';
import { AuthLayout } from 'layouts/AuthLayout';

import { MembersContent } from 'shared/resources/members/MembersContent';
import type { ProjectHandover } from 'shared/resources/members/projectHandover';

interface Props {
  users: Member[];
  projectHandover?: ProjectHandover | null;
}

function MembersIndex({ users, projectHandover }: Props) {
  return (
    <AuthLayout>
      <MembersContent
        users={users}
        basePath="/company/members"
        projectHandover={projectHandover}
        title="Company Members"
        subtitle="People with access to this company workspace. Admins manage members, integrations, and settings; employees and viewers work within projects."
      />
    </AuthLayout>
  );
}

export default MembersIndex;
