import type { Member } from '@/types/generated';
import { AuthLayout } from 'layouts/AuthLayout';

import type { InviteProject } from 'shared/resources/members/InviteMemberDrawer';
import { MembersContent } from 'shared/resources/members/MembersContent';
import type { ProjectHandover } from 'shared/resources/members/projectHandover';
import { companyMembersPath } from 'shared/routes';

interface Props {
  users: Member[];
  projectHandover?: ProjectHandover | null;
  inviteProjects?: InviteProject[];
}

function MembersIndex({ users, projectHandover, inviteProjects }: Props) {
  return (
    <AuthLayout>
      <MembersContent
        users={users}
        basePath={companyMembersPath()}
        projectHandover={projectHandover}
        inviteProjects={inviteProjects}
        title="Company Members"
        subtitle="People with access to this company workspace. Admins manage members, integrations, and settings; employees and viewers work within projects."
      />
    </AuthLayout>
  );
}

export default MembersIndex;
