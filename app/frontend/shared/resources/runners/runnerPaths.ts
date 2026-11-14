import {
  companyProjectRunnerPath,
  companyProjectRunnersPath,
  companySettingsRunnerPath,
  companySettingsRunnersPath,
  disableCompanyProjectRunnerPath,
  disableCompanySettingsRunnerPath,
  enableCompanyProjectRunnerPath,
  enableCompanySettingsRunnerPath,
  registrationTokenCompanyProjectRunnerPath,
  registrationTokenCompanySettingsRunnerPath,
  returnToServiceCompanyProjectRunnerMachinePath,
  returnToServiceCompanySettingsRunnerMachinePath,
  revokeCompanyProjectRunnerMachinePath,
  revokeCompanyProjectRunnerPath,
  revokeCompanySettingsRunnerMachinePath,
  revokeCompanySettingsRunnerPath,
} from 'shared/routes';

import type { RunnerPaths } from './runnerConfig';

export const companyRunnerPaths = (): RunnerPaths => ({
  list: companySettingsRunnersPath(),
  runner: (id) => companySettingsRunnerPath(id),
  disable: (id) => disableCompanySettingsRunnerPath(id),
  enable: (id) => enableCompanySettingsRunnerPath(id),
  revoke: (id) => revokeCompanySettingsRunnerPath(id),
  registrationToken: (id) => registrationTokenCompanySettingsRunnerPath(id),
  returnToService: (id, machineId) => returnToServiceCompanySettingsRunnerMachinePath(id, machineId),
  revokeMachine: (id, machineId) => revokeCompanySettingsRunnerMachinePath(id, machineId),
});

export const projectRunnerPaths = (projectId: number): RunnerPaths => ({
  list: companyProjectRunnersPath(projectId),
  runner: (id) => companyProjectRunnerPath(projectId, id),
  disable: (id) => disableCompanyProjectRunnerPath(projectId, id),
  enable: (id) => enableCompanyProjectRunnerPath(projectId, id),
  revoke: (id) => revokeCompanyProjectRunnerPath(projectId, id),
  registrationToken: (id) => registrationTokenCompanyProjectRunnerPath(projectId, id),
  returnToService: (id, machineId) => returnToServiceCompanyProjectRunnerMachinePath(projectId, id, machineId),
  revokeMachine: (id, machineId) => revokeCompanyProjectRunnerMachinePath(projectId, id, machineId),
});
