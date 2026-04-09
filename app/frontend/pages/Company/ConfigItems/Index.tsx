import { AuthLayout } from 'layouts/AuthLayout';

import { ConfigItemsContent, type ConfigItem } from 'shared/resources/config-items/ConfigItemsContent';

interface Props {
  configItems: ConfigItem[];
}

function ConfigItemsIndex({ configItems }: Props) {
  return (
    <AuthLayout>
      <ConfigItemsContent configItems={configItems} basePath="/company/config_items" title="Config Items" />
    </AuthLayout>
  );
}

export default ConfigItemsIndex;
