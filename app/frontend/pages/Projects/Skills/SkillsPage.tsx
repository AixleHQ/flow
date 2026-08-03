import { Head, usePage } from '@inertiajs/react';

import { SkillsContent, type CatalogSkill, type Skill } from 'shared/resources/skills/SkillsContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Project {
  id: number;
  name: string;
}

interface Props {
  project: Project;
  skills: Skill[];
  catalogQuery: string;
  catalogSkills: CatalogSkill[];
  catalogSyncedAt: string | null;
}

const SkillsPage = () => {
  const { project, skills, catalogQuery, catalogSkills, catalogSyncedAt } = usePage<{ props: Props }>()
    .props as unknown as Props;

  return (
    <>
      <Head title={`Skills — ${project.name}`} />
      <SkillsContent
        skills={skills}
        basePath={`/company/projects/${project.id}/skills`}
        title="Project Skills"
        subtitle="Skills this project can use — installed from the public catalog or written by hand."
        catalogQuery={catalogQuery}
        catalogSkills={catalogSkills}
        catalogSyncedAt={catalogSyncedAt}
      />
    </>
  );
};

setPageLayout(SkillsPage, persistentProjectLayout);

export default SkillsPage;
