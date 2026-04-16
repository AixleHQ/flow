import { AuthLayout } from 'layouts/AuthLayout';

import { MembersContent, type MemberUser } from 'shared/resources/members/MembersContent';

interface Props {
  users: MemberUser[];
}

function MembersIndex({ users }: Props) {
  return (
    <AuthLayout>
      <MembersContent users={users} basePath="/company/members" title="Company Members" />
    </AuthLayout>
  );
}

export default MembersIndex;
