# Domain-Specific Requirements

## Compliance & Regulatory

| Requirement | Priority | Notes |
|-------------|----------|-------|
| **SOC 2 Type II** | High (for public SaaS) | Required when opening to external customers |
| **GDPR basics** | Medium | User data handling, right to deletion |

**SOC 2 Trust Service Criteria:**
- Security — access controls, encryption, monitoring
- Availability — uptime, disaster recovery
- Confidentiality — data protection, secrets management
- Processing Integrity — accurate data processing
- Privacy — personal data handling

## Technical Constraints

| Constraint | Requirement |
|------------|-------------|
| **Secrets Security** | Encrypted at rest, secrets hierarchy (Platform → Company → Workflow) |
| **Multi-tenancy Isolation** | Data isolation between companies, container isolation between sessions |
| **Audit Logging** | All actions logged for SOC 2 compliance |
| **Encryption** | TLS in transit, encryption at rest for sensitive data |

## Key Architecture Decisions

> See [Workflow Architecture](./workflow-architecture.md) for full details.

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Tool calling mechanism | MCP servers | Standard protocol, works with all CLI agents |
| Workflow steps | Sequential only | Simplicity for MVP, no parallel execution |
| Branching in workflows | Not supported | UI shows step status (done/running/pending) instead |
| Workspace structure | `/input/` (readonly) + `/output/` (collect) | Simple, predictable artifact flow |
| Artifact versioning | Parent chain (v1 → v2 → v3) | Track changes across workflow runs |
| MCP server lifecycle | Per-session | Server starts with session, stops when session ends |

## Integration Requirements

| Integration | Purpose |
|-------------|---------|
| **LLM Providers** | Anthropic, OpenAI, OpenRouter — provider agnostic |
| **Linear** | Task export from planning workflows |
| **GitHub/GitLab** | PR creation, code context |
| **S3** | Artifact storage |

## Risk Mitigations

| Risk | Mitigation |
|------|------------|
| **Runaway API costs** | Budget alerts, rate limiting, cost tracking per session |
| **Data leakage between tenants** | Strict isolation, separate containers, access controls |
| **LLM provider outage** | Fallback to alternative providers |
| **Secrets exposure** | Encrypted storage, audit logs, rotation policies |

---
