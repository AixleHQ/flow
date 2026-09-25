import { Head, usePage } from '@inertiajs/react';

import type { CatalogSkill, Project, Skill } from '@/types/generated';

import { SkillsContent } from 'shared/resources/skills/SkillsContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Props {
  project: Project;
  skills: Skill[];
  archivedSkills: Skill[];
  catalogQuery: string;
  catalogSkills: CatalogSkill[];
  catalogSyncedAt: string | null;
}

const SkillsPage = () => {
  const { project, skills, archivedSkills, catalogQuery, catalogSkills, catalogSyncedAt } = usePage<{ props: Props }>()
    .props as unknown as Props;

  return (
    <>
      <Head title={`Skills — ${project.name}`} />
      <SkillsContent
        skills={skills}
        archivedSkills={archivedSkills}
        projectId={project.id}
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
