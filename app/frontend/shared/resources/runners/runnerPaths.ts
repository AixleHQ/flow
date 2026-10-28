import {
  companyProjectRunnerPath,
  companyProjectRunnersPath,
  companySettingsRunnerPath,
  companySettingsRunnersPath,
  disableCompanyProjectRunnerPath,
  disableCompanySettingsRunnerPath,
  enableCompanyProjectRunnerPath,
  enableCompanySettingsRunnerPath,
  revokeCompanyProjectRunnerPath,
  revokeCompanySettingsRunnerPath,
} from 'shared/routes';

import type { RunnerPaths } from './runnerConfig';

export const companyRunnerPaths = (): RunnerPaths => ({
  list: companySettingsRunnersPath(),
  runner: (id) => companySettingsRunnerPath(id),
  disable: (id) => disableCompanySettingsRunnerPath(id),
  enable: (id) => enableCompanySettingsRunnerPath(id),
  revoke: (id) => revokeCompanySettingsRunnerPath(id),
});

export const projectRunnerPaths = (projectId: number): RunnerPaths => ({
  list: companyProjectRunnersPath(projectId),
  runner: (id) => companyProjectRunnerPath(projectId, id),
  disable: (id) => disableCompanyProjectRunnerPath(projectId, id),
  enable: (id) => enableCompanyProjectRunnerPath(projectId, id),
  revoke: (id) => revokeCompanyProjectRunnerPath(projectId, id),
});
