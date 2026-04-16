import { AuthLayout } from 'layouts/AuthLayout';

import { Integration, IntegrationsContent } from 'shared/resources/integrations/IntegrationsContent';

interface Props {
  integrations: Integration[];
}

function IntegrationsIndex({ integrations }: Props) {
  return (
    <AuthLayout>
      <IntegrationsContent integrations={integrations} basePath="/company/integrations" title="Integrations" />
    </AuthLayout>
  );
}

export default IntegrationsIndex;
