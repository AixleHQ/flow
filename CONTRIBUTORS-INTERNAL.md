# Internal Contributor Notes

> Not linked from the public README. This file documents commands and
> integrations that only apply to Palad AI team members. External
> contributors do not need any of this.

## AWS Vault Configuration

Add your profile:

```bash
aws-vault add {your_aws_vault_profile}
```

## Remote Execution

The previous README documented `make qa-web-exec` and `make login_aws`
targets, but those targets are **not currently in the Makefile**. Use
the AWS / kubectl commands directly until they are restored. Talk to
the platform team for the current procedure.

## Secrets and 1Password

`.env.example` references several values stored in 1Password (GitHub
App credentials, Bitbucket OAuth, GitLab OAuth, Skills API key). Team
members pull them from the shared vault.

## Internal Architecture References

The `ai/` directory contains internal design docs and epics — these
are historical artifacts of how the platform was built, not user-facing
documentation. The public-facing reference lives under `docs/`.

- `ai/epic-8-unified-container-architecture.md` — original design for
  the Container Execution Framework (`app/services/container_strategies/`)
- `references/aixle-system-reference.md` — full domain model reference
  used by the internal Aixle Builder agent
- `docs/palad-strategy-draft.md` — internal product strategy draft

## Database Dumps

```bash
make db_dump            # dump local DB and upload to S3
make db_restore_remote  # restore from S3 (uses DATABASE_* env vars)
make restore-dump       # restore from local /db_dumps/latest.sql.gz
```
