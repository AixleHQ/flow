# Privacy Policy — Aixle Flow

**Last updated:** August 6, 2026 · **Effective:** August 6, 2026

## 1. Who We Are

Aixle Flow ("the Service") is provided by Dualboot Partners, LLC ("Dualboot," "we," "us"), 5540 Centerview Dr., Ste. 204, #24754, Raleigh, NC 27606.

## 2. Two Deployment Models

The Service is available in two forms, and our role differs between them. This distinction determines most of what follows.

**Hosted (we operate it):** We run the infrastructure. Our role under GDPR is Processor on behalf of the customer organization, which is the controller. We are an independent controller only for account and billing data. What we can see is everything described in Section 3. This policy applies in full.

**Self-hosted (you operate it):** You run the infrastructure, on your own systems. We are neither controller nor processor — we do not receive, access, or store your data. This policy applies only to Sections 1, 9, and 10.

The Service's source code is available under the Apache License 2.0. If you deploy it yourself, we have no visibility into your data and no ability to access it, and you are the controller for all data you process with it.

## 3. What We Collect (Hosted Deployments)

**3.1 Account and identity data.** Collected when a user signs in through a supported identity provider (we support Google OpenID Connect, and request only the user's email address and basic profile) or, where enabled for an organization, through a password credential issued in the product: email address, display name, profile picture URL, job title, identity-provider identifiers and access tokens, password hash where password sign-in is used, role within the organization, organization membership, invitation records, interface language preference, and timestamps of account creation, invitation, onboarding, and sign-in.

**3.2 Organization and project configuration.** Organization name, identifier, email domain, branding, and settings; projects and project membership; repository names, URLs, descriptions, and default branches; connected integrations (source-control, issue-tracker, messaging, and infrastructure providers) and their credentials in encrypted form; MCP server definitions and their configuration values; agent, skill, tool, workflow, and board definitions; and resource quotas.

**3.3 Credentials for your AI-assistant accounts.** When a user onboards an AI coding assistant (for example Claude Code, Codex, Cursor CLI, or Gemini CLI), the Service captures and stores, in encrypted form, the authentication artifacts that the assistant's own client produces — an OAuth token set or an API key for that user's account with the AI provider — together with metadata such as expiry, the model selected, and when the credential was last used. These credentials are injected into the container at the start of a session so the agent can authenticate to the provider, and are used for no other purpose.

**3.4 Session inputs and repository content.** For each session: the instruction or prompt submitted; the session configuration and injected context; the source code and repository contents retrieved from your connected source-control systems into the session's container; files the agent creates or modifies; artifacts collected at the end of a session; files and assets your users upload; and the text of board tasks and comments, whether written by a person or by an agent.

**3.5 Session transcripts and captured provider traffic.** The Service retains, as files:

- A complete capture of the session terminal — everything submitted by the user and everything produced by the agent during the session, including source-code contents, command output, and file paths.
- A log of the agent's network traffic to its AI provider, recorded by a proxy inside the container. For agents where this is enabled, it contains the complete body of each request and response — that is, the prompts and any file content sent with them, and the model's replies — together with the request and response headers.

This content is stored as submitted or as produced. It is not redacted, filtered, or reduced. Because it is whatever a developer instructed an agent to do and whatever the agent did in response, it may contain information we cannot anticipate — including source code, credentials, your customers' data, and personal data relating to people who are not our users. We do not seek this data and cannot control what appears in it.

Our Terms of Service require customers not to knowingly submit special-category personal data (as defined under Article 9 of the GDPR), payment-card data, or regulated health data to the Service. Because session content is captured as submitted or produced, we cannot verify or enforce compliance with that restriction at the point of submission, and this section describes what may occur in practice notwithstanding that contractual restriction.

**3.6 Usage and cost records.** For each session: the agent and models used, input, output, and cached token counts, computed cost, event counts and the underlying usage events, session duration and state, the associated project and repositories, and the identity of the user who initiated it. These are collected from telemetry the agent emits and from the traffic described in Section 3.5.

**3.7 Data received from your connected systems.** Where you connect a source-control, issue-tracker, or messaging provider, we receive and store the payloads those systems send us, which typically include commit, branch, and pull-request metadata and the names and email addresses of the people who authored them. Those people may not be users of the Service.

**3.8 Technical and diagnostic data.** Server logs, IP addresses, request metadata, and error reports (including stack traces and request context). Retained for security, debugging, and abuse prevention.

**3.9 What we do not collect.** We do not collect payment-card data. We do not use advertising or cross-site tracking technologies. We do not sell personal data. We do not request access to your email, calendar, files, or other data held by your identity provider.

## 4. Why We Process It; Legal Basis

| Purpose | Data | Legal basis (GDPR) |
|---|---|---|
| Providing the Service to the customer organization — running agent sessions and workflows on its instructions | Sections 3.1–3.7 | Performance of a contract (Art. 6(1)(b)); for individual developers, the customer's legitimate interest (Art. 6(1)(f)), subject to Section 6 of our Terms of Service |
| Authentication and access control | Sections 3.1, 3.3 | Contract; legitimate interest (Art. 6(1)(f)) |
| Cost and usage reporting to the customer organization | Sections 3.2, 3.6 | Performance of a contract (Art. 6(1)(b)) |
| Security, abuse prevention, and debugging | Sections 3.1, 3.8 | Legitimate interest (Art. 6(1)(f)) |
| Improving the Service | Aggregated and de-identified data only | Legitimate interest (Art. 6(1)(f)) |
| Legal and regulatory compliance | As required | Legal obligation (Art. 6(1)(c)) |

We do not rely on any legal basis for using session content or source code to train machine-learning models, because we do not do so. Section 4.4 of our Terms of Service commits us not to.

## 5. Sub-processors and Third Parties

Company may engage third-party service providers, contractors, and subprocessors ("Subprocessors") to perform functions and provide services to Company in connection with the Service.

Company may add, remove, or replace Subprocessors from time to time as necessary to operate and improve the Service. Where Company processes personal data on behalf of a customer as a data processor under applicable data protection law, the specific terms governing Subprocessor engagement, notice, and objection rights are set forth in the applicable Data Processing Addendum, which shall control over this Section in the event of any conflict.

Separately from our Subprocessors, the AI providers your users connect to the Service necessarily receive the content an agent sends to them, authenticated with the credentials described in Section 3.3. Those providers process that content under their own terms, as described in Section 5.3 of our Terms of Service. The providers the Service supports today are Anthropic, OpenAI, Cursor, and Google.

## 6. Retention

We retain the data described in Section 3 for as long as your organization maintains an account, except where a shorter period is stated below.

| Data | Retention |
|---|---|
| Account and organization data (Sections 3.1–3.2) | For the life of the account, and up to 30 days after its deletion |
| Credentials for AI-assistant accounts (Section 3.3) | Until the user replaces them, deletes them, or the account is deleted |
| Session inputs, artifacts, and assets (Section 3.4) | For the life of the account, unless you delete them earlier |
| Session transcripts and captured provider traffic (Section 3.5) | For the life of the account, unless you delete them earlier |
| Usage and cost records (Section 3.6) | For the life of the account, and as required for billing and financial records |
| Payloads from connected systems (Section 3.7) | For the life of the account, unless you delete them earlier |
| Tool execution results | 30 days |
| Technical and diagnostic data (Section 3.8) | Per the retention period of our error-monitoring provider |

You may ask us to delete session records, transcripts, artifacts, or your account at any time using the contact details in Section 13, and we will do so except where we are required to retain data by law. On termination, our retention obligations are as set out in Section 14.3 of our Terms of Service.

## 7. Your Rights

Depending on your location you may have rights to access, correct, delete, port, restrict, or object to the processing of your personal data, and to withdraw consent where processing relies on it.

**If you are a developer using the Service through your employer's organization account:** that organization is the controller of the data described in Section 3. Requests should ordinarily be directed to your employer. We will assist them and will not respond directly except where required by law or instructed by the controller. Contact us using the details in Section 13 if you cannot reach the controller.

The customer organization's obligations to its personnel regarding notice, consultation, and legal basis — including any works council or employee-representative consultation required by Applicable Law — are addressed in Section 6 (Visibility of Individual Usage and Personnel Monitoring) of our Terms of Service, which the customer organization agrees to as a condition of using the Service.

Complaints may be lodged with your local supervisory authority.

## 8. Reserved.

## 9. International Transfers

We are a US-based company. If you access the Service from outside the United States, your personal data will be transferred to, stored, and processed in the United States, and may be transferred to other jurisdictions where our sub-processors operate (see Section 5).

Where a transfer involves personal data originating in the European Economic Area, the United Kingdom, or Switzerland to a country not recognized as providing an adequate level of data protection, we will implement an appropriate transfer mechanism recognized under Applicable Law — such as the European Commission's Standard Contractual Clauses, the UK International Data Transfer Addendum, or a valid EU-U.S. Data Privacy Framework self-certification — before making such transfer.

## 10. Security

We maintain technical and organizational measures designed to protect the data described in Section 3, including encryption of data in transit, isolation of each agent session in its own container, separation of compute by project and by user, encryption of connected credentials at rest, access controls limiting internal access to personal data on a need-to-know basis, and network security controls appropriate to a hosted service.

Providing the Service inherently requires processing the content of your sessions — the instructions you give an agent, the source code it works on, and the traffic it exchanges with its AI provider (see Section 3.5). This is a necessary consequence of the Service's core function of running agents on your code on your behalf, not a byproduct of how we handle security. We do not currently redact or filter that content before it is stored. As a result, session records may contain information you or your personnel did not intend to retain, including credentials and information relating to third parties. We describe this here so that customers and their personnel can make an informed decision about what to submit to the Service. We may introduce redaction capabilities in the future; until then, this section reflects current practice.

Our operational staff can access account, session, and session-record data through an internal administrative console where necessary to provide, secure, support, or troubleshoot the Service. Complete session transcripts and captured provider traffic (Section 3.5) are reachable in that way; they are not exposed in the customer-facing interface. Within your organization account, session records and usage — including the instruction submitted with each session — are visible to every member of that account, not only to administrators; the controls available to you are described in Section 6.6 of our Terms of Service.

No method of transmission or storage is completely secure, and we cannot guarantee the absolute security of your data.

## 11. Children

The Service is not directed to individuals under the age of 18, and we do not knowingly collect personal data from children. If you believe a child has provided us with personal data, please contact us using the details in Section 13 and we will take steps to investigate and, where appropriate, delete it.

## 12. Changes

We may update this Privacy Policy from time to time. If we make material changes, we will provide reasonable notice (for example, by email to the account administrator or an in-app notice) before the changes take effect. The "Last updated" date above indicates when this Policy was last revised.

## 13. Contact

Questions about this Privacy Policy, or requests relating to your personal data, should be directed to Dualboot Partners, LLC, 5540 Centerview Dr., Ste. 204, #24754, Raleigh, NC 27606, or by email to privacy@aixle.com.
