import { AuthLayout } from 'layouts/AuthLayout';

import { SkillsContent, type Skill, type RegistrySkill } from 'shared/resources/skills/SkillsContent';

interface Props {
  skills: Skill[];
  registryQuery: string;
  registryResults: RegistrySkill[];
}

function SkillsIndex({ skills, registryQuery, registryResults }: Props) {
  return (
    <AuthLayout>
      <SkillsContent
        skills={skills}
        basePath="/company/skills"
        title="Company Skills"
        subtitle="Skills from skills.sh registry installed for this company. Available in all projects."
        registryQuery={registryQuery}
        registryResults={registryResults}
      />
    </AuthLayout>
  );
}

export default SkillsIndex;
