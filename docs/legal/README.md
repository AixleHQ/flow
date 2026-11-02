# Legal documents

The hosted product (`Deployment.saas?`) publishes three documents under `/legal`. A
self-hosted or AWS Marketplace installation publishes none of them: `/legal/*` answers
404 there, and nobody is asked to accept anything.

| Document | Page | Source | Who accepts it, and when |
|---|---|---|---|
| Terms of Service (Aixle Standard Terms and Conditions, with the SLA, DPA and BAA as Exhibits A–C) | `/legal/terms_of_service` | `app/views/web/legal/terms_of_service.html.erb` | A company's representative, for the company: the person creating a workspace ticks the box on `/workspace/new`; for a company created any other way, or after a new version, the next admin to enter it |
| Terms of Use | `/legal/terms_of_use` | `app/views/web/legal/terms_of_use.html.erb` | Every user, for themselves: on the workspace form when they create one, otherwise on their first sign-in, and again after a new version |
| Privacy Policy | `/legal/privacy_policy` | `app/views/web/legal/privacy_policy.html.erb` | Nobody — it is a notice, not an agreement |

`/legal` lists them. The old `/privacy-policy` and `/terms-of-service` addresses redirect.

## How acceptance works

`LegalDocument` (`app/models/legal_document.rb`) holds each document's `version` — the date
its text last changed. Each acceptance is a `LegalAcceptance` row naming the document and
version, the user, the company (Terms of Service only), the time, the IP address and the
browser user agent. Rows are never updated.

A row is evidence that outlives what it names. It carries the user's email and the
company's name and email domain in its own columns, and deleting the user or the company
nullifies the reference but keeps the row.

The time, IP address and user agent are those of the request that ticked the box. For a
stranger's signup that is the form they sent, not the link they open later: the evidence
travels in the emailed link (`WorkspaceSignupTicket`), which is encrypted for that reason.

`Web::ApplicationController#enforce_legal_acceptance` runs after the company's auth policy
and before onboarding. While the signed-in user has not accepted the current Terms of Use,
or is an admin of a company that has not accepted the current Terms of Service, every web
page redirects to `/legal/accept`. Employees and viewers are never asked about the Terms of
Service. Super admins and impersonated sessions are never held, and an impersonating
operator cannot accept on someone's behalf.

`Settings.legal.acceptance_required` turns the gate off; it is `false` only in
`config/settings/test.yml`, where tests of the gate turn it on.

## Publishing a new version

1. Replace the text in the view. The Terms of Service and Terms of Use are converted from
   the lawyers' `.docx` with section numbering kept; the only intended difference from
   the `.docx` is that URLs point at `https://flow.aixle.com/legal/...`.
2. Set the document's `version` in `LegalDocument::ALL` to the new date, in the same change.
   That is what asks everyone to accept again — a text change without a version bump asks
   nobody.
3. Record the version and the new digest of the view in `PUBLISHED` in
   `test/models/legal_document_test.rb`. That test fails on any edit to a document's view
   until this is done, and its message prints the digest. An edit that does not change
   what the document says (a typo, markup) records the new digest and keeps the version.
4. Add a `CHANGELOG.md` entry.
