import { Head, usePage } from '@inertiajs/react';

import type { Project, Repository } from '@/types/generated';

import { RepositoriesContent } from 'shared/resources/repositories/RepositoriesContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Props {
  project: Project;
  repositories: Repository[];
  editBranches?: string[];
}

const RepositoriesPage = () => {
  const { project, repositories, editBranches } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <>
      <Head title={`Repositories — ${project.name}`} />
      <RepositoriesContent
        repositories={repositories}
        editBranches={editBranches}
        basePath={`/company/projects/${project.id}/repositories`}
        title="Repositories"
      />
    </>
  );
};

setPageLayout(RepositoriesPage, persistentProjectLayout);

export default RepositoriesPage;
