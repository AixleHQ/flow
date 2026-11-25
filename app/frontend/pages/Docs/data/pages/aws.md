# AWS

The AWS integration lets a workflow step use an IAM role in your AWS account without an access
key. Flow acts as an OpenID Connect identity provider that your account trusts. When
a step needs AWS, Flow assumes the role with `AssumeRoleWithWebIdentity` and hands the
step credentials that last at most an hour. No long-lived key exists in Flow, in the
step's container or in your account.

It connects per project, from the project's **Integrations** page.

This page walks through one setup end to end, then covers what a step sees, the
subjects a trust policy can name, troubleshooting and limits.

---

## What you need

- Rights to create an IAM OIDC identity provider and an IAM role in the AWS account.
- A Flow instance AWS can reach over HTTPS. The hosted platform qualifies. A
  self-hosted instance behind a VPN does not, because AWS fetches Flow's signing
  keys from the public internet.
- A workflow whose steps need AWS. The example below is a workflow that reads an
  application's CloudWatch logs and queries an Aurora database through the RDS Data
  API, then replies with a diagnosis.

## How it fits together

| Piece | Lives in | What it decides |
|---|---|---|
| Issuer | Flow, one per project integration | Which Flow project AWS is talking to |
| IAM OIDC identity provider | Your AWS account | That the account trusts this issuer |
| IAM role and its trust policy | Your AWS account | Which workflows and steps may assume the role (`sub`) |
| The role's permission policy | Your AWS account | What the role may do once assumed |
| Role in Flow, attached to a step | Flow | Which steps Flow hands credentials to |

A step gets credentials only when both sides agree: Flow attaches the role to the
step, and the role's trust policy allows the step's subject.

---

## Walkthrough

### 1. Connect AWS

On the project's **Integrations** page, choose **Connect → AWS**. Flow creates the
project's issuer and opens the AWS dialog. **Manage** on the integration's row
opens it again later. Copy two values from it:

| Value | Example |
|---|---|
| Issuer URL | `https://flow.example.com/oidc/9fK2…` |
| Audience | `sts.amazonaws.com` |

The issuer belongs to this project's integration only. An AWS account that trusts it
trusts this project, never another project or company on the same Flow.

### 2. Add the identity provider in AWS

Each AWS account a step should reach needs its own provider for the same issuer.

**Console.** IAM → **Identity providers** → **Add provider** → **OpenID Connect**.
Provider URL: the issuer URL. Audience: `sts.amazonaws.com`. No thumbprint is needed.

**CLI.**

```bash
aws iam create-open-id-connect-provider \
  --url https://flow.example.com/oidc/9fK2... \
  --client-id-list sts.amazonaws.com
```

**Terraform.**

```hcl
resource "aws_iam_openid_connect_provider" "flow" {
  url            = "https://flow.example.com/oidc/9fK2..."
  client_id_list = ["sts.amazonaws.com"]
}
```

IAM no longer needs a thumbprint. If your AWS provider version still asks for
`thumbprint_list`, upgrade it.

### 3. Create the role

Create a role with only what the workflow needs. For the example: Logs Insights and
`FilterLogEvents` on the application's log groups, the RDS Data API on one cluster, and
the one secret the Data API reads the database user from.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "QueryAppLogs",
      "Effect": "Allow",
      "Action": ["logs:StartQuery", "logs:FilterLogEvents"],
      "Resource": "arn:aws:logs:us-east-1:123456789012:log-group:/ecs/app*"
    },
    {
      "Sid": "ReadQueryResults",
      "Effect": "Allow",
      "Action": ["logs:GetQueryResults", "logs:StopQuery", "logs:DescribeLogGroups"],
      "Resource": "*"
    },
    {
      "Sid": "QueryDatabase",
      "Effect": "Allow",
      "Action": ["rds-data:ExecuteStatement", "rds-data:BatchExecuteStatement"],
      "Resource": "arn:aws:rds:us-east-1:123456789012:cluster:aurora-main"
    },
    {
      "Sid": "ReadDatabaseUser",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:us-east-1:123456789012:secret:aurora-main-readonly-*"
    }
  ]
}
```

`rds-data:ExecuteStatement` runs any SQL the database user allows, so make read-only a
property of the database too: the secret should hold a read-only Postgres user, ideally
limited to the tables or views the diagnosis needs.

**Console.** IAM → **Roles** → **Create role** → **Web identity**. Pick the provider and
the audience `sts.amazonaws.com`, attach the permission policy, name the role and create
it. Then replace its trust policy with the one Flow generates (step 4): the console's
default trusts every subject of the issuer and lacks `sts:TagSession`.

### 4. Add the role in Flow and set its trust policy

In the AWS dialog, choose **Add role** and enter:

| Field | Meaning |
|---|---|
| Name | The profile name the step sees, in lowercase letters, digits and dashes, e.g. `prod-diag` |
| Role ARN | The role you created |
| Region | The default region written into the profile |
| Session duration | 900 to 3600 seconds, and no more than the role's own maximum |

Under **Trust policy**, pick the role. The policy trusts every workflow of this project and
the dialog's Verify; which steps actually get the role is decided by attaching it in the
builder (step 6). Tick **Allow draft test runs** if test runs of unsaved drafts may use it
too, and **Only specific workflows** if your AWS admin wants AWS to check the workflow as
well. **Copy policy** and paste it as the role's trust policy in AWS:

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
        "flow.example.com/oidc/9fK2...:sub": ["workflow:*", "verify:integration:3"]
      }
    }
  }]
}
```

With the CLI: `aws iam update-assume-role-policy --role-name flow-prod-diagnostics
--policy-document file://trust.json`. With Terraform, put the same document in the role's
`assume_role_policy`.

`sts:TagSession` is required: Flow tags each session with the project, workflow, step,
run, session and user ids, so CloudTrail shows which run held the role. AWS evaluates
only `aud` and `sub` from the token; conditions on any other claim never match.

### 5. Verify

Press **Verify** next to the role. Flow assumes it with the verify subject, asks STS who
that is, shows the assumed-role ARN and drops the credentials. When it fails, the dialog
says what AWS refused; see [Troubleshooting](#troubleshooting).

Flow cannot list your roles: it holds no permission in your account. Verify is how you
know a role works before a run needs it.

### 6. Attach the role to a step

In the workflow builder, pick the role under **AWS roles** on the steps that need it, or
on the **Base Resources** tab to give it to every step of the workflow. A role reaches a
step only this way: **Inherit all project resources** does not include roles, and a
session started by hand never has one.

Over the personal MCP server, `list_aws_oidc_roles` lists a project's roles with their
ids, and `create_workflow_step`, `update_workflow_step` and `update_workflow` attach them
(`aws_oidc_role_ids`, `base_aws_oidc_role_ids`).

### 7. Write the step

The agent's context lists the profiles the step has, so the instructions only need to
say what to look at. For the example's log step:

```text
Find the errors in /ecs/app in the 30 minutes before the time in the thread.
Use `aws --profile prod-diag logs start-query` and `get-query-results`,
summarise the top three error messages with counts, and quote one example of each.
```

### 8. Run it and check

Run the workflow. The dialog's **Activity** lists each time a step received credentials:
when, which role, which workflow and step, which run and for whom. In CloudTrail, the
role session name is `flow-session-<session id>`.

---

## What the step sees

The step's container gets one profile per role in `~/.aws/config`:

```ini
[profile prod-diag]
credential_process = /usr/local/bin/aixle-aws-creds --role prod-diag
region = eu-west-1
```

There is no key in it. The AWS CLI and every AWS SDK call the helper when they need
credentials, and Flow returns ones that last at most the role's session duration, then
fresh ones as they expire. A step with one role and no Bedrock connection also gets the
role as `[default]`; otherwise name the profile with `aws --profile prod-diag …` or
`AWS_PROFILE=prod-diag`. An MCP server that calls AWS needs `AWS_PROFILE` in its own env,
because a stdio server does not inherit the agent's environment.

The agent can read these credentials, as it can read anything in its container. What
bounds them is the role's permissions and their lifetime, so give the role only what the
step needs. A workflow that posts its findings to a channel shares what the role can read
with everyone in that channel.

## Subjects

The `sub` claim says which run is asking. A trust policy allows the subjects it names
and nothing else.

| Run | `sub` |
|---|---|
| A workflow step | `workflow:<workflow id>:step:<step id>` |
| A test run of a draft | `draft:workflow:<workflow id>:step:<step id>` |
| The dialog's **Verify** | `verify:integration:<integration id>` |

Ids never change when something is renamed. The generated policy allows `workflow:*`,
every workflow of the project; with **Only specific workflows** it lists
`workflow:12:step:*` for each one picked, and a hand-written policy can go down to one step,
`workflow:12:step:34`. A draft uses the ids of the workflow
and step it was copied from, behind `draft:`, so unsaved changes reach the role only if
the policy names drafts too. A step added in a draft has no source step and appears as
`step:new-<id>`.

## Troubleshooting

| What you see | Usually means | Fix |
|---|---|---|
| Verify: "AWS could not get Flow's signing key from …" | AWS cannot read the issuer: the integration is disconnected, the instance is not reachable from the internet, or the provider was created for another URL | Reconnect; check the provider URL is exactly the issuer URL |
| Verify: "AWS rejected the token …" | No provider for this issuer in the role's account, or the provider lacks the audience `sts.amazonaws.com` | Add the provider in that account (step 2), with the audience |
| Verify: "The role's trust policy rejected subject …" | The trust policy does not list that subject, or lacks `sts:TagSession` | Paste the generated policy again, with the verify subject |
| Verify: "AWS refused the request for this role …" | The session duration is above the role's maximum | Lower it in Flow, or raise the role's maximum session duration |
| A run: the AWS CLI says it cannot get credentials from the custom process | The role is not attached to that step, or the integration is disconnected | Attach the role to the step; check the integration's status |
| A run: `AccessDenied` from CloudWatch, RDS or another service | The role was assumed; its permission policy does not allow the call | Extend the role's permission policy, not its trust policy |
| A draft's test run is refused, the published workflow works | The trust policy does not name `draft:` subjects | Tick **Allow draft test runs** and paste the policy again |
| An MCP server in the step cannot find credentials | It does not inherit `AWS_PROFILE` from the agent | Set `AWS_PROFILE` in the MCP server's env |

## Disconnect and remove

- **Disconnect** keeps the issuer and the roles, and makes the issuer answer 404:
  AWS refuses every token from the project until you press **Reconnect**, which brings
  back the same issuer. Use it to stop everything at once.
- **Remove** on the Integrations page deletes the integration, its roles and their
  attachments to steps. Connecting again creates a new issuer, so every provider and
  trust policy has to be set up again.

## Limits

- Workflow steps only. An interactive session cannot have a role.
- Credentials last 15 to 60 minutes and are fetched again as they expire.
- A template never carries roles: an ARN belongs to one account. After installing a
  template, attach the project's own roles to its steps.

## See also

- [Integrations](/docs/integrations)
- [Workflows](/docs/workflows)
