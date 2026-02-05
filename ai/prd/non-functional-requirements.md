# Non-Functional Requirements

## Security

| ID | Requirement | Rationale |
|----|-------------|-----------|
| **NFR-S1** | All API keys and secrets encrypted at rest (AES-256) | Protect sensitive credentials |
| **NFR-S2** | All data in transit encrypted via TLS 1.2+ | Standard security practice |
| **NFR-S3** | Session data isolated by company_id — no cross-tenant access | Multi-tenancy isolation |
| **NFR-S4** | Audit log for all admin actions (user management, secrets, workflows) | SOC 2 preparation |
| **NFR-S5** | Secrets never logged or displayed after creation | Prevent credential exposure |
| **NFR-S6** | Docker containers isolated per session | Prevent cross-session data leakage |

## Reliability

| ID | Requirement | Rationale |
|----|-------------|-----------|
| **NFR-R1** | Session failure rate < 1% | Core success metric |
| **NFR-R2** | Zero data loss for artifacts (stored in S3 with redundancy) | Business critical |
| **NFR-R3** | Billing accuracy ≥ 95% of actual token usage | Key differentiator |
| **NFR-R4** | Graceful degradation when LLM provider unavailable | Fallback to alternative |
| **NFR-R5** | Session state preserved on unexpected termination | User doesn't lose work |

## Integration

| ID | Requirement | Rationale |
|----|-------------|-----------|
| **NFR-I1** | Support multiple LLM providers (Anthropic, OpenAI, OpenRouter) | Provider agnostic |
| **NFR-I2** | MITM proxy compatible with all 4 target agents | Core billing feature |
| **NFR-I3** | GitHub API integration for repo access and PR creation | Core workflow feature |
| **NFR-I4** | Linear API integration for task export | Planning workflow output |
| **NFR-I5** | Temporal orchestration for all workflow execution | Reliability, retry, visibility |

## Operability

| ID | Requirement | Rationale |
|----|-------------|-----------|
| **NFR-O1** | Structured logging for all services | Debugging, monitoring |
| **NFR-O2** | Health checks for all containers | Kubernetes readiness |
| **NFR-O3** | Temporal UI accessible for workflow debugging | Developer experience |
