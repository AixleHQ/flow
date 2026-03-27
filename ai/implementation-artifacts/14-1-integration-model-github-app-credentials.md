# Story 14.1: Integration Model + GitHub App Credentials

Status: review

## Story

As an admin,
I want to connect a GitHub App to my company,
so that the platform can access GitHub repositories on behalf of the organization.

## Acceptance Criteria

1. **Integration model** — `belongs_to :company`. Fields: `provider` (enumerize: github, linear), `name` (string, e.g. org name), `credentials` (encrypted jsonb), `settings` (jsonb), `status` (enumerize: active, inactive, error), `connected_by_id` (User). Multiple integrations per provider per company allowed (e.g. service company with multiple client GitHub orgs).
2. **Platform-level GitHub App config** — `app_id` and `private_key` are platform-wide settings (Settings/env), NOT per-integration. One GitHub App for the entire platform. Integration stores only `installation_id` (per GitHub org where App is installed).
3. **Setup URL flow** — Admin clicks "Connect GitHub" → redirected to GitHub App installation page → installs App on their org (selects repos) → GitHub redirects back with `installation_id` → system creates Integration automatically. Name auto-populated from org name via `GET /app/installations/{id}` → `account.login`.
4. **Connection test** — On creation, system generates JWT from platform app_id + private_key, exchanges for installation access token, verifies access. Sets status to `active` or `error`.
5. **API endpoints** — `Api::V1::Company::IntegrationsController` — index, create (from callback), show, destroy. Scoped to company admin.
6. **Serializer** — Returns name, provider, status, settings, connected_by, connected_at, repos_count. Never returns credentials.
7. **UI** — Company Settings → Integrations tab. List of connected integrations with org name, status, repo count. "Connect GitHub" button triggers setup flow.

## Tasks / Subtasks

- [x] Task 1: Database migration (AC: #1)
  - [x] 1.1 Create `integrations` table: `name` (string, not null), `provider` (string, not null), `credentials` (text — encrypted jsonb), `settings` (jsonb, default: {}), `status` (string, not null, default: 'inactive'), `company_id` (bigint, not null, FK), `connected_by_id` (bigint, not null, FK to users), `timestamps`
  - [x] 1.2 Add indexes: `[company_id, provider]` (not unique — multiple per provider allowed), `[company_id]`, `[status]`

- [x] Task 2: Integration model (AC: #1, #2, #4)
  - [x] 2.1 `belongs_to :company`, `belongs_to :connected_by, class_name: 'User'`
  - [x] 2.2 Enumerize `provider`: `%i[github linear]`
  - [x] 2.3 Enumerize `status`: `%i[active inactive error]`, default: `:inactive`
  - [x] 2.4 Validations: name presence, provider presence, company presence
  - [x] 2.5 Encrypted credentials using `ActiveSupport::MessageEncryptor` — follow AgentCredential pattern. Methods: `credentials_data=` (encrypts hash to JSON string), `credentials_data` (decrypts). Encryption key: `Settings.encryption.integrations_key`
  - [x] 2.6 Scopes: `for_company(company)`, `github`, `linear`, `active`
  - [ ] 2.7 `has_many :repositories, dependent: :destroy` — **deferred to Story 14.2** (repositories table doesn't exist yet)
  - [x] 2.8 Add `has_many :integrations, dependent: :destroy` to Company model

- [x] Task 3: GitHub token service (AC: #2, #4)
  - [x] 3.1 Create `Github::TokenService` in `app/services/github/token_service.rb`
  - [x] 3.2 Method `generate_installation_token(integration)` — reads platform `Settings.github.app_id` and `Settings.github.private_key_path` (path to PEM file), generates JWT (RS256, 10min TTL), exchanges via `POST /app/installations/{installation_id}/access_tokens`, returns token string
  - [x] 3.3 Method `verify_installation(integration)` — generates token, calls `GET /app/installations/{installation_id}`, returns installation info (org name, account type, permissions)
  - [x] 3.4 Uses `octokit` gem (already in Gemfile) for GitHub API calls
  - [x] 3.5 Add `jwt` gem to Gemfile

- [x] Task 4: Settings configuration (AC: #2)
  - [x] 4.1 Add to `config/settings.yml`: `github.app_id`, `github.app_slug`, `github.private_key_path` (from env vars)
  - [x] 4.2 Add to `config/settings.yml`: `encryption.integrations_key` (from env var: `INTEGRATIONS_SECRET_KEY`)
  - [x] 4.3 Private key stored as PEM file on disk (mounted as secret in production), path in settings

- [x] Task 5: API controller (AC: #3, #5)
  - [x] 5.1 `Api::V1::Company::IntegrationsController` — index, show, create, destroy
  - [x] 5.2 `index` — list all integrations for current company, include repos_count
  - [x] 5.3 `create` — accepts `{ installation_id: "..." }`, calls `Github::TokenService.verify_installation` to get org name, creates Integration with status `:active` or `:error`
  - [x] 5.4 `destroy` — hard-deletes integration
  - [x] 5.5 `github_callback` — dedicated action for GitHub App setup URL redirect
  - [x] 5.6 Routes: `resources :integrations, only: %i[index show create destroy]` + `collection { get :github_callback }`

- [x] Task 6: Serializer (AC: #6)
  - [x] 6.1 `IntegrationSerializer < ApplicationSerializer` — id, name, provider, status, settings, connected_by (nested), created_at, repos_count
  - [x] 6.2 `repos_count` — graceful fallback (0) until repositories association exists
  - [x] 6.3 NEVER serialize `credentials` field

- [x] Task 7: Policy (AC: #5)
  - [x] 7.1 `Api::V1::Company::IntegrationsPolicy` — all actions require `current_user.admin?`

- [x] Task 8: Frontend — RTK Query API (AC: #7)
  - [x] 8.1 Create `features/integrations-management/api/integrationsApi.ts`
  - [x] 8.2 Endpoints: `getCompanyIntegrations` (query), `createGithubIntegration` (mutation), `deleteIntegration` (mutation)
  - [x] 8.3 Add `QueryTag.Integrations` to `shared/api/QueryTag.ts`
  - [x] 8.4 Types in `features/integrations-management/lib/types.ts`

- [x] Task 9: Frontend — Integrations UI (AC: #7)
  - [x] 9.1 Create `features/integrations-management/ui/IntegrationsPanel.tsx` — list of integrations with cards (org name, GitHub icon, status chip, repos count, delete button)
  - [x] 9.2 "Connect GitHub" button — opens GitHub App installation URL in new tab via `VITE_GITHUB_APP_SLUG` env var
  - [x] 9.3 Handle callback redirect — detects `installation_id` in URL search params, calls create mutation
  - [x] 9.4 Create `pages/integrations/ui/IntegrationsPage.tsx` — thin wrapper
  - [x] 9.5 Add route to `routeTree.tsx` and `shared/routes.ts`
  - [x] 9.6 Add navigation link in AppHeader nav items

- [x] Task 10: Tests (AC: all)
  - [x] 10.1 Integration model test — 18 tests: validations, enumerize, encryption round-trip, scopes, associations
  - [x] 10.2 Github::TokenService test — 5 tests: mock Octokit, JWT generation, verify_installation, error cases
  - [x] 10.3 IntegrationsController test — 12 tests: index, show, create (mocked), destroy, authorization
  - [x] 10.4 Factory: `integration` factory with traits `:github`, `:linear`, `:active`, `:error`

## Dev Notes

### Architecture Decision: Integration Model

Integration is **company-level only** (not polymorphic scope). Rationale: GitHub App installation is per-org, not per-project. One company connects to one or more GitHub orgs. Repositories (Story 14.2) are then scoped to company/project.

### Encryption Pattern — Follow AgentCredential

Use the **exact same pattern** as `AgentCredential` model:

```ruby
# web/app/models/agent_credential.rb pattern:
def credentials_data=(hash)
  self.credentials = encrypt(hash.to_json)
end

def credentials_data
  return {} if credentials.blank?
  JSON.parse(decrypt(credentials))
rescue JSON::ParserError
  {}
end

private

def encrypt(plain_text)
  encryptor.encrypt_and_sign(plain_text)
end

def decrypt(cipher_text)
  encryptor.decrypt_and_verify(cipher_text)
end

def encryptor
  @encryptor ||= ActiveSupport::MessageEncryptor.new(encryption_key)
end

def encryption_key
  Settings.encryption.integrations_key.to_s.ljust(32, "0")[0..31]
end
```

The `credentials` DB column stores the encrypted string. `credentials_data` accessor encrypts/decrypts a hash. For GitHub: `{ installation_id: "12345" }`. For Linear (future): `{ access_token: "...", refresh_token: "..." }`.

### GitHub App Auth Flow

```
Platform-level (Settings):
  github.app_id = "123456"
  github.private_key_path = "/secrets/github-app.pem"

Per-Integration:
  credentials_data = { installation_id: "789" }

Token generation (on-demand, never cached):
  1. Read PEM: OpenSSL::PKey::RSA.new(File.read(Settings.github.private_key_path))
  2. JWT payload: { iat: Time.now.to_i, exp: 10.minutes.from_now.to_i, iss: Settings.github.app_id }
  3. JWT: JWT.encode(payload, private_key, "RS256")
  4. Octokit client: Octokit::Client.new(bearer_token: jwt)
  5. Token: client.create_app_installation_access_token(installation_id)
  6. Return: token.token (string, lives 1 hour)
```

### GitHub App Setup URL Flow

1. Admin clicks "Connect GitHub" → opens `https://github.com/apps/{APP_SLUG}/installations/new` in new tab
2. User installs App on their GitHub org, selects repos
3. GitHub redirects to setup URL: `https://app.example.com/api/v1/company/integrations/github_callback?installation_id=12345`
4. Controller creates Integration, verifies with GitHub API, sets name from org
5. Redirects to integrations page with success flash

The `APP_SLUG` comes from `Settings.github.app_slug` (the URL-friendly name of the GitHub App).

### Existing Patterns to Follow

**Model pattern** — Follow `AgentCredential` for encryption, standard ActiveRecord for the rest:
- `web/app/models/agent_credential.rb` — encrypted config_data pattern
- Encryption key in Settings: `Settings.encryption.integrations_key`

**Controller pattern** — Follow `Api::V1::Company::SkillsController`:
- `web/app/controllers/api/v1/company/skills_controller.rb`
- Pundit authorization via `dynamic_authorize!`
- Response via `respond_with` + serializer

**Serializer pattern** — Follow `SkillSerializer`:
- `web/app/serializers/skill_serializer.rb`

**Policy pattern** — Follow `Api::V1::Company::SkillsPolicy`:
- `web/app/policies/api/v1/company/skills_policy.rb`
- Admin-only for all actions

**Frontend API pattern** — Follow `skillsApi.ts`:
- `web/app/frontend/features/skills-management/api/skillsApi.ts`
- RTK Query `injectEndpoints`, `QueryTag`, `providesTags`/`invalidatesTags`

**Frontend UI pattern** — Follow `SkillsPage.tsx`:
- `web/app/frontend/features/skills-management/ui/SkillsPage.tsx`
- Card/list layout, action buttons, status indicators

### Key Gems

- `octokit` — Already in Gemfile. Use for all GitHub API calls.
- `jwt` — **Need to add**. Use for RS256 JWT generation. `gem 'jwt', '~> 2.9'`
- `config` — Already in Gemfile. Use for `Settings.github.*`

### Settings to Add

```yaml
# config/settings.yml
github:
  app_id: <%= ENV['GITHUB_APP_ID'] %>
  app_slug: <%= ENV['GITHUB_APP_SLUG'] %>
  private_key_path: <%= ENV['GITHUB_PRIVATE_KEY_PATH'] || 'config/github-app.pem' %>

encryption:
  integrations_key: <%= ENV['INTEGRATIONS_SECRET_KEY'] || "integrations test key" %>
```

### Project Structure Notes

Backend files to create:
- `web/app/models/integration.rb`
- `web/app/services/github/token_service.rb`
- `web/app/controllers/api/v1/company/integrations_controller.rb`
- `web/app/serializers/integration_serializer.rb`
- `web/app/policies/api/v1/company/integrations_policy.rb`
- `web/db/migrate/YYYYMMDD_create_integrations.rb`

Frontend files to create:
- `web/app/frontend/features/integrations-management/api/integrationsApi.ts`
- `web/app/frontend/features/integrations-management/lib/types.ts`
- `web/app/frontend/features/integrations-management/ui/IntegrationsPanel.tsx`
- `web/app/frontend/pages/integrations/ui/IntegrationsPage.tsx`

### References

- [Source: ai/epics/epic-14-external-integrations-phase-7.md#Story 14.1]
- [Source: ai/prd/functional-requirements.md#FR66]
- [Source: ai/project-context.md#Technology Stack]
- [Pattern: web/app/models/agent_credential.rb — encryption]
- [Pattern: web/app/models/skill.rb — model structure]
- [Pattern: web/app/controllers/api/v1/company/skills_controller.rb — controller]
- [Pattern: web/app/frontend/features/skills-management/ — frontend]

## Dev Agent Record

### Agent Model Used
Claude claude-4.6-opus-max-thinking

### Debug Log References
- Fixed encryption rescue clause: added `ActiveSupport::MessageEncryptor::InvalidMessage` to rescue list
- Deferred `has_many :repositories` to Story 14.2 (repositories table does not exist yet); serializer uses graceful fallback returning 0
- Pre-existing test failure in `AssetsControllerTest#test_#upload_stores_file_in_cache_and_returns_location` unrelated to this story

### Completion Notes List
- All 7 acceptance criteria satisfied
- 35 new tests (18 model, 5 service, 12 controller), all passing
- Full regression suite: 970 tests, 1 pre-existing failure, 0 new failures
- Subtask 2.7 (`has_many :repositories`) deferred to Story 14.2 — comment placeholder added in model

### File List
- `web/db/migrate/20260219100000_create_integrations.rb` (new)
- `web/app/models/integration.rb` (new)
- `web/app/models/company.rb` (modified — added `has_many :integrations`)
- `web/app/services/github/token_service.rb` (new)
- `web/app/controllers/api/v1/company/integrations_controller.rb` (new)
- `web/app/serializers/integration_serializer.rb` (new)
- `web/app/policies/api/v1/company/integrations_policy.rb` (new)
- `web/config/routes.rb` (modified — added integrations routes)
- `web/config/settings.yml` (modified — added github + integrations_key settings)
- `web/Gemfile` (modified — added jwt gem)
- `web/app/frontend/shared/api/QueryTag.ts` (modified — added Integrations tag)
- `web/app/frontend/shared/api/routes.ts` (modified — added integration route functions)
- `web/app/frontend/shared/routes.ts` (modified — added companyIntegrationsPath)
- `web/app/frontend/features/integrations-management/api/integrationsApi.ts` (new)
- `web/app/frontend/features/integrations-management/lib/types.ts` (new)
- `web/app/frontend/features/integrations-management/ui/IntegrationsPanel.tsx` (new)
- `web/app/frontend/pages/integrations/ui/IntegrationsPage.tsx` (new)
- `web/app/frontend/pages/integrations/index.ts` (new)
- `web/app/frontend/app/routeTree.tsx` (modified — added IntegrationsPage route)
- `web/app/frontend/widgets/AppHeader/ui/AppHeader.tsx` (modified — added nav link)
- `web/test/factories/integrations.rb` (new)
- `web/test/models/integration_test.rb` (new)
- `web/test/services/github/token_service_test.rb` (new)
- `web/test/controllers/api/v1/company/integrations_controller_test.rb` (new)

## Change Log
- 2026-02-19: Story 14.1 implemented — Integration model with encrypted credentials, GitHub token service, API + UI, 35 new tests
Guide: Creating a GitHub App
Step 1: Registration
GitHub → Settings → Developer Settings → GitHub Apps → New GitHub App
Fill in:
Name: your-app-name (unique across all of GitHub)
Homepage URL: the URL of your application
Webhook: Deactivate (uncheck Active — webhooks are not needed)
Callback URL: https://your-app.com/auth/github/callback (for the OAuth installation flow)
Step 2: Permissions
Minimal set:
Permission	Access	Why
Contents	Read & Write	Clone repo + push branches
Pull requests	Read & Write	Creating PRs
Metadata	Read-only	List of repositories (required)
Step 3: After creation
You will note the App ID (numeric)
You will generate a Private Key (.pem file) — it downloads automatically
These two values are stored in the Integration model (encrypted)
Step 4: Installation on an organization/account
From the App page → Install App
Select org/account → select repositories (All or specific ones)
After installation, the URL will contain installation_id — we also save it