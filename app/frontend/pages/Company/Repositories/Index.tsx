import { AuthLayout } from 'layouts/AuthLayout';

import { Repository, RepositoriesContent } from 'shared/resources/repositories/RepositoriesContent';

interface Props {
  repositories: Repository[];
  editBranches?: string[];
}

function RepositoriesIndex({ repositories, editBranches }: Props) {
  return (
    <AuthLayout>
      <RepositoriesContent
        repositories={repositories}
        editBranches={editBranches}
        basePath="/company/repositories"
        title="Repositories"
      />
    </AuthLayout>
  );
}

export default RepositoriesIndex;
