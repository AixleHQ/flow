import { Head, usePage } from '@inertiajs/react';

import { SkillsContent, type Skill, type RegistrySkill } from 'shared/resources/skills/SkillsContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Project {
  id: number;
  name: string;
}

interface Props {
  project: Project;
  skills: Skill[];
  registryQuery: string;
  registryResults: RegistrySkill[];
}

const SkillsPage = () => {
  const { project, skills, registryQuery, registryResults } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <>
      <Head title={`Skills — ${project.name}`} />
      <SkillsContent
        skills={skills}
        basePath={`/company/projects/${project.id}/skills`}
        title="Project Skills"
        subtitle="Skills from skills.sh registry installed for this project."
        registryQuery={registryQuery}
        registryResults={registryResults}
      />
    </>
  );
};

setPageLayout(SkillsPage, persistentProjectLayout);

export default SkillsPage;
