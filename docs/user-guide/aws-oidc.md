# AWS OIDC

AWS OIDC lets a workflow step use an IAM role in your AWS account without an access
key. Flow acts as an OpenID Connect identity provider that your account trusts. When
a step needs AWS, Flow assumes the role with `AssumeRoleWithWebIdentity` and hands the
step credentials that last at most an hour. No long-lived key exists in Flow, in the
step's container or in your account.

AWS OIDC connects per project. It is behind a feature flag: if **AWS OIDC** is missing
from the connect menu on the project's **Integrations** page, ask us to turn it on.

---

## What you need

- Rights to create an IAM OIDC identity provider and an IAM role in the AWS account.
- A Flow instance AWS can reach over HTTPS. The hosted platform qualifies. A
  self-hosted instance behind a VPN does not, because AWS fetches Flow's signing
  keys from the public internet.

## Connect

On the project's **Integrations** page, choose **Connect → AWS OIDC**. Flow creates
the project's issuer and opens the AWS OIDC dialog with two values. **Manage** on
the integration's row opens it again later.

| Value | Example |
|---|---|
| Issuer URL | `https://flow.example.com/oidc/9fK2…` |
| Audience | `sts.amazonaws.com` |

The issuer belongs to this project's integration only. An AWS account that trusts it
trusts this project, never another project or company on the same Flow.

## Create the provider and the role in AWS

1. In IAM, add an **OpenID Connect** identity provider with the issuer URL as the
   provider URL and `sts.amazonaws.com` as the audience. Each account a step should
   reach needs its own provider for the same issuer.
2. Create a role for that provider. Give it only what the step needs: specific log
   groups, one database, one secret.
3. Set its trust policy. In the AWS OIDC dialog, add the role (next section), pick the
   workflows that may use it, and copy the generated policy. It looks like this:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::123456789012:oidc-provider/flow.example.com/oidc/9fK2..." },
    "Action": ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"],
    "Condition": {
      "StringEquals": { "flow.example.com/oidc/9fK2...:aud": "sts.amazonaws.com" },
      "StringLike": {
        "flow.example.com/oidc/9fK2...:sub": ["workflow:12:step:*", "verify:integration:3"]
      }
    }
  }]
}
```

`sts:TagSession` is required: Flow tags each session with the project, workflow,
step, run, session and user ids, so CloudTrail shows which run held the role.

### Subjects

The `sub` claim says which run is asking. A trust policy allows the subjects it names
and nothing else.

| Run | `sub` |
|---|---|
| A workflow step | `workflow:<workflow id>:step:<step id>` |
| A test run of a draft | `draft:workflow:<workflow id>:step:<step id>` |
| The dialog's **Verify** | `verify:integration:<integration id>` |

Ids never change when something is renamed. A draft uses the ids of the workflow and
step it was copied from, behind `draft:`, so unsaved changes reach the role only if
the policy names drafts too. A step added in a draft has no source step and appears
as `step:new-<id>`.

## Add the role in Flow

In the AWS OIDC dialog, choose **Add role** and enter:

| Field | Meaning |
|---|---|
| Name | The profile name the step sees, in lowercase letters, digits and dashes, e.g. `prod-diag` |
| Role ARN | The role you created |
| Region | The default region written into the profile |
| Session duration | 900 to 3600 seconds, and no more than the role's own maximum |

Flow cannot list your roles: it holds no permission in your account. Press **Verify**
to check a role. Flow assumes it with the verify subject, asks STS who that is, shows
the assumed-role ARN and drops the credentials. When it fails, the dialog says what
AWS refused: no provider for the issuer, a trust policy that does not allow the
subject or `sts:TagSession`, or a duration above the role's maximum.

## Attach the role to a step

In the workflow builder, pick the role under **AWS roles** on a step, or on the
workflow to give it to every step. A role reaches a step only this way: **Inherit all
project resources** does not include roles, and a session started by hand never has
one.

Over the personal MCP server, `list_aws_oidc_roles` lists a project's roles with their
ids, and `create_workflow_step`, `update_workflow_step` and `update_workflow` attach them
(`aws_oidc_role_ids`, `base_aws_oidc_role_ids`).

## What the step sees

The step's container gets one profile per role in `~/.aws/config`:

```ini
[profile prod-diag]
credential_process = /usr/local/bin/aixle-aws-creds --role prod-diag
region = eu-west-1
```

There is no key in it. The AWS CLI and every AWS SDK call the helper when they need
credentials, and Flow returns ones that last at most the role's session duration. A
step with one role and no Bedrock connection also gets the role as `[default]`;
otherwise name the profile with `aws --profile prod-diag …` or `AWS_PROFILE=prod-diag`.
An MCP server that calls AWS needs `AWS_PROFILE` in its own env, because a stdio
server does not inherit the agent's environment. The agent's context lists the
profiles it has.

The agent can read these credentials, as it can read anything in its container. What
bounds them is the role's permissions and their lifetime, so give the role only what
the step needs. A workflow that posts its findings to a channel shares what the role
can read with everyone in that channel.

## Disconnect and remove

- **Disconnect** keeps the issuer and the roles, and makes the issuer answer 404:
  AWS refuses every token from the project until you press **Reconnect**, which brings
  back the same issuer. Use it to stop everything at once.
- **Remove** on the Integrations page deletes the integration, its roles and their
  attachments to steps. Connecting again creates a new issuer, so every trust policy
  has to be set up again.

## Activity

The dialog lists the last times a step received credentials: when, which role, which
workflow and step, which run and for whom. CloudTrail has the AWS side, under the role
session name `flow-session-<session id>`.

## Limits

- Workflow steps only. An interactive session cannot have a role.
- Credentials last 15 to 60 minutes and are fetched again as they expire.
- A template never carries roles: an ARN belongs to one account. After installing a
  template, attach the project's own roles to its steps.

## See also

- [Integrations](integrations.md)
- [Workflows](workflows.md)
