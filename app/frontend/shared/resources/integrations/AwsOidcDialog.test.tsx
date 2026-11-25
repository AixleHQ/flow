import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { act, within } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import {
  buildAwsOidcActivity,
  buildAwsOidcConnection,
  buildAwsOidcProps,
  buildAwsOidcRole,
  buildAwsOidcVerifyResult,
} from 'test/factories/awsOidc';
import { answerFetch } from 'test/fetchStub';
import { renderPage, screen, userEvent } from 'test/renderPage';

import type { AwsOidcProps } from './awsOidcActions';
import { AwsOidcDialog } from './AwsOidcDialog';

const VERIFY_ROUTE = 'POST /company/projects/3/aws_oidc/roles/1/verify';

const openDialog = async (awsOidc: AwsOidcProps = buildAwsOidcProps()) => {
  renderPage(<AwsOidcDialog opened onClose={vi.fn()} projectId={3} awsOidc={awsOidc} />);
  return screen.findByRole('dialog', { name: 'AWS OIDC' });
};

describe('AwsOidcDialog', () => {
  beforeEach(() => vi.clearAllMocks());

  it('shows the issuer and audience to copy, and the roles', async () => {
    const dialog = await openDialog();

    expect(within(dialog).getByText('https://flow.example.com/oidc/9fK2abc')).toBeInTheDocument();
    expect(within(dialog).getByText('sts.amazonaws.com')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Copy issuer url' })).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Copy audience' })).toBeInTheDocument();

    const row = within(dialog).getByRole('row', { name: /prod-diagnose/ });
    expect(within(row).getByText('arn:aws:iam::123456789012:role/flow-diagnose')).toBeInTheDocument();
    expect(within(row).getByText('eu-west-1')).toBeInTheDocument();
    expect(within(row).getByText('60 min')).toBeInTheDocument();
  });

  it('verifies a role and shows the role AWS assumed', async () => {
    answerFetch({ [VERIFY_ROUTE]: buildAwsOidcVerifyResult() });
    const dialog = await openDialog();

    await userEvent.click(within(dialog).getByRole('button', { name: 'Verify prod-diagnose' }));

    expect(
      await within(dialog).findByText(
        'Verified: AWS assumed arn:aws:sts::123456789012:assumed-role/flow-diagnose/flow-verify-1',
      ),
    ).toBeInTheDocument();
  });

  it('shows why AWS refused the role', async () => {
    answerFetch({
      [VERIFY_ROUTE]: buildAwsOidcVerifyResult({
        ok: false,
        assumed_role_arn: null,
        failure: 'trust_policy',
        message: "The role's trust policy rejected subject verify:integration:9.",
      }),
    });
    const dialog = await openDialog();

    await userEvent.click(within(dialog).getByRole('button', { name: 'Verify prod-diagnose' }));

    expect(
      await within(dialog).findByText("The role's trust policy rejected subject verify:integration:9."),
    ).toBeInTheDocument();
  });

  it('adds a role, and keeps the form open with the reason when it is refused', async () => {
    const dialog = await openDialog(buildAwsOidcProps({ connection: buildAwsOidcConnection({ roles: [] }) }));
    expect(within(dialog).getByText(/No roles yet/)).toBeInTheDocument();

    await userEvent.click(within(dialog).getByRole('button', { name: 'Add role' }));
    await userEvent.type(within(dialog).getByLabelText('Name'), 'prod-read');
    await userEvent.type(within(dialog).getByLabelText('Role ARN'), 'arn:aws:iam::123456789012:role/read');
    await userEvent.type(within(dialog).getByLabelText('Region'), 'us-east-1');
    const duration = within(dialog).getByLabelText('Session duration (seconds)');
    await userEvent.clear(duration);
    await userEvent.type(duration, '1800');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Add role' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/3/aws_oidc/roles',
      {
        aws_oidc_role: {
          name: 'prod-read',
          role_arn: 'arn:aws:iam::123456789012:role/read',
          region: 'us-east-1',
          session_duration_seconds: 1800,
        },
      },
      expect.objectContaining({ preserveScroll: true }),
    );
    const options = vi.mocked(router.post).mock.lastCall?.[2] as {
      onError?: (errors: Record<string, string>) => void;
      onFinish?: () => void;
    };
    act(() => {
      options.onError?.({ roleArn: 'Role arn must be an IAM role ARN' });
      options.onFinish?.();
    });
    expect(within(dialog).getByText('Role arn must be an IAM role ARN')).toBeInTheDocument();
    expect(within(dialog).getByLabelText('Name')).toHaveValue('prod-read');
  });

  it('edits a role in place', async () => {
    const dialog = await openDialog();

    await userEvent.click(within(dialog).getByRole('button', { name: 'Edit prod-diagnose' }));
    const region = within(dialog).getByLabelText('Region');
    await userEvent.clear(region);
    await userEvent.type(region, 'eu-central-1');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save role' }));

    expect(router.patch).toHaveBeenCalledWith(
      '/company/projects/3/aws_oidc/roles/1',
      {
        aws_oidc_role: {
          name: 'prod-diagnose',
          role_arn: 'arn:aws:iam::123456789012:role/flow-diagnose',
          region: 'eu-central-1',
          session_duration_seconds: 3600,
        },
      },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('asks before deleting a role', async () => {
    const dialog = await openDialog();

    await userEvent.click(within(dialog).getByRole('button', { name: 'Delete prod-diagnose' }));
    const confirm = await screen.findByRole('dialog', { name: 'Delete role' });
    await userEvent.click(within(confirm).getByRole('button', { name: 'Delete' }));

    expect(router.delete).toHaveBeenCalledWith('/company/projects/3/aws_oidc/roles/1', { preserveScroll: true });
  });

  it("generates the role's trust policy for the picked workflows", async () => {
    const dialog = await openDialog();

    await userEvent.click(within(dialog).getByRole('combobox', { name: 'Workflows' }));
    await userEvent.click(await screen.findByRole('option', { name: 'Prod diagnosis' }));
    await userEvent.click(within(dialog).getByRole('checkbox', { name: /Allow draft test runs/ }));

    const policy = JSON.parse(within(dialog).getByLabelText('Trust policy').textContent ?? '');
    expect(policy.Statement[0].Principal.Federated).toBe(
      'arn:aws:iam::123456789012:oidc-provider/flow.example.com/oidc/9fK2abc',
    );
    expect(policy.Statement[0].Condition.StringLike['flow.example.com/oidc/9fK2abc:sub']).toEqual([
      'workflow:12:step:*',
      'draft:workflow:12:step:*',
      'verify:integration:9',
    ]);
    expect(within(dialog).getByRole('button', { name: 'Copy policy' })).toBeInTheDocument();
  });

  it('generates a policy for a role not added yet from its account ID', async () => {
    const dialog = await openDialog(buildAwsOidcProps({ connection: buildAwsOidcConnection({ roles: [] }) }));

    expect(within(dialog).queryByLabelText('Trust policy')).not.toBeInTheDocument();
    await userEvent.type(within(dialog).getByLabelText('AWS account ID'), '210987654321');

    expect(within(dialog).getByLabelText('Trust policy')).toHaveTextContent(
      'arn:aws:iam::210987654321:oidc-provider/flow.example.com/oidc/9fK2abc',
    );
  });

  it('lists the last uses of the roles', async () => {
    const dialog = await openDialog(
      buildAwsOidcProps({ connection: buildAwsOidcConnection({ activity: [buildAwsOidcActivity()] }) }),
    );

    const row = within(dialog).getByRole('row', { name: /Prod diagnosis · Diagnose/ });
    expect(within(row).getByRole('link', { name: '#501' })).toHaveAttribute(
      'href',
      '/company/projects/3/workflow_runs/501',
    );
    expect(within(row).getByText('Ada')).toBeInTheDocument();
  });

  it('is read-only for someone who cannot manage it', async () => {
    const dialog = await openDialog(buildAwsOidcProps({ canManage: false }));

    expect(within(dialog).getByRole('row', { name: /prod-diagnose/ })).toBeInTheDocument();
    expect(within(dialog).queryByRole('button', { name: 'Add role' })).not.toBeInTheDocument();
    expect(within(dialog).queryByRole('button', { name: 'Verify prod-diagnose' })).not.toBeInTheDocument();
    expect(within(dialog).queryByRole('button', { name: 'Delete prod-diagnose' })).not.toBeInTheDocument();
    expect(within(dialog).getByLabelText('Trust policy')).toBeInTheDocument();
  });

  it('says a disconnected issuer is refused, and reconnects', async () => {
    const dialog = await openDialog(
      buildAwsOidcProps({ connection: buildAwsOidcConnection({ status: 'inactive', roles: [buildAwsOidcRole()] }) }),
    );

    expect(within(dialog).getByText(/AWS refuses every token from this project/)).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Reconnect' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/3/aws_oidc/connect',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );
  });
});
