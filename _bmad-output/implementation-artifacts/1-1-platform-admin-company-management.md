# Story 1.1: Platform Admin Company Management

Status: ready-for-dev

## Story

As a super admin,
I want to create companies and specify their email domains,
So that users with matching email domains are automatically assigned to the correct company.

## Acceptance Criteria

1. **Given** I am a super admin
   **When** I navigate to the Platform Admin panel at `/admin`
   **Then** I can see a list of all companies with basic information (name, slug, domains, user count, state)
   **And** I can click on a company to view its details

2. **Given** I am a super admin on the companies index page
   **When** I click "Create New Company"
   **Then** I see a form to create a new company with fields:
   - Company name (required)
   - Email domain(s) (required, comma-separated, e.g., "company.com, subsidiary.com")
   - Initial admin email (optional)
   **When** I submit the form with valid data
   **Then** the company is created with all provided information
   **And** I am redirected to the company details page
   **And** I see a success message confirming the company was created

3. **Given** a company exists with email domain "example.com"
   **When** a user with email "@example.com" signs in via Google OAuth for the first time
   **Then** they are automatically assigned to this company
   **And** if they match the initial admin email, they are assigned the `admin` role
   **And** otherwise they are assigned the `collaborator` role (default)

4. **Given** I am a super admin viewing a company
   **When** I click "Edit Company"
   **Then** I can modify:
   - Company name
   - Email domain(s)
   - State (active, suspended, archived)
   - Branding fields (display name, logo URL, colors)
   **When** I save changes
   **Then** the company is updated
   **And** existing users remain assigned to the company
   **And** future sign-ins match the updated domains

5. **Given** I am a super admin viewing a company
   **When** I click "Delete Company"
   **Then** I see a confirmation dialog warning about consequences:
   - "This will delete all users, projects, and data for this company. This action cannot be undone."
   **When** I confirm the deletion
   **Then** the company and all associated data are deleted (via `dependent: :destroy`)
   **And** I am redirected to the companies index page
   **And** I see a success message

6. **Given** I am not a super admin (I am a regular `admin` or `collaborator`)
   **When** I try to access `/admin` or any admin routes
   **Then** I am redirected to the login page
   **And** I see an error message: "You must be a super admin to access this page"

## Tasks / Subtasks

- [ ] Task 1: Add email domains field to Company model (AC: 2, 3, 4)
  - [ ] Generate migration to add `email_domains` JSONB column to companies table
  - [ ] Add validation: `email_domains` must be an array of valid email domains
  - [ ] Add helper method `domains` that returns parsed email_domains array
  - [ ] Add helper method `matches_domain?(email)` to check if email matches any domain
  - [ ] Update Company model with new validation and methods

- [ ] Task 2: Create Admin::CompaniesController (AC: 1, 2, 4, 5)
  - [ ] Generate `Admin::CompaniesController` using Administrate gem
  - [ ] Ensure it inherits from `Admin::ApplicationController` (already has super_admin authentication)
  - [ ] Add standard CRUD actions: index, show, new, create, edit, update, destroy
  - [ ] Add user_count to index query using counter cache or SQL count
  - [ ] Add confirmation and safeguards for destroy action
  - [ ] Use `Admin::CompanyDashboard` for field configuration

- [ ] Task 3: Create Admin::CompanyDashboard for Administrate (AC: 1, 2, 4)
  - [ ] Create `app/dashboards/company_dashboard.rb` (already exists - verify and update)
  - [ ] Add `email_domains` field as `Field::Text` (displays as comma-separated string)
  - [ ] Add `initial_admin_email` field as `Field::String` (optional)
  - [ ] Add `users` association as `Field::HasMany` to show user count
  - [ ] Include `state` enumerize field using `DashboardConcern` (already implemented)
  - [ ] Include branding fields (display_name, logo_url, primary_color, secondary_color)
  - [ ] Ensure COLLECTION_ATTRIBUTES shows: id, name, slug, state, user_count
  - [ ] Ensure SHOW_PAGE_ATTRIBUTES includes all relevant fields + users association

- [ ] Task 4: Update Google OAuth callback to assign company by domain (AC: 3)
  - [ ] Locate OAuth callback controller (e.g., `SessionsController` or `OmniauthCallbacksController`)
  - [ ] Add logic to find company by email domain after successful OAuth
  - [ ] If multiple companies match, choose the first one (or implement priority logic)
  - [ ] If no company matches, leave `company_id` as nil (or create default company later)
  - [ ] If `initial_admin_email` matches user email, assign `admin` role
  - [ ] Otherwise assign `collaborator` role (default)
  - [ ] Handle edge case: User already exists (update company_id if changed)
  - [ ] Add logging for company assignment decisions

- [ ] Task 5: Update Admin routes to include companies resource (AC: 1)
  - [ ] Update `web/config/routes.rb` to include `resources :companies` in admin namespace
  - [ ] Verify root route `/admin` points to `Admin::UsersController#index` (from Story 1.0)
  - [ ] Consider changing root to `Admin::CompaniesController#index` (better UX for super admin)
  - [ ] Ensure all routes are protected by `Admin::ApplicationController` authentication

- [ ] Task 6: Add controller tests for Admin::CompaniesController (AC: 1-6)
  - [ ] Create `test/controllers/admin/companies_controller_test.rb`
  - [ ] Inherit from `Admin::ActionControllerTestCase` (defined in `test_helper.rb`)
  - [ ] Use factories and sequences for all test data (no hardcoded values)
  - [ ] Test cases:
    - `test "should get index"` - super admin can view companies list
    - `test "should get new"` - super admin can view new company form
    - `test "should create company"` - super admin can create company with email domains
    - `test "should show company"` - super admin can view company details
    - `test "should get edit"` - super admin can view edit form
    - `test "should update company"` - super admin can update company (name, domains, state)
    - `test "should destroy company"` - super admin can delete company
    - `test "non-super-admin cannot access companies index"` - regular admin/collaborator is denied

- [ ] Task 7: Update User factory to support company assignment (AC: 3)
  - [ ] Update `test/factories/users.rb` to ensure `:with_company` trait works correctly
  - [ ] Add trait `:matches_domain` that creates user with email matching a company's domain
  - [ ] Ensure factory uses sequences for email generation

- [ ] Task 8: Add integration test for OAuth company assignment (AC: 3)
  - [ ] Create `test/integration/oauth_company_assignment_test.rb` (or update existing OAuth tests)
  - [ ] Test case: User signs in with email matching company domain → assigned to company
  - [ ] Test case: User signs in with initial_admin_email → assigned `admin` role
  - [ ] Test case: User signs in with non-matching email → no company assigned (or default)
  - [ ] Test case: Existing user signs in → company_id remains unchanged (or updated based on logic)

## Dev Notes

### Architecture Requirements

**From Architecture Document (ai/architecture.md):**
- **Authentication:** Google OAuth via OmniAuth - [Source: ai/architecture.md#Authentication--Security]
- **Authorization:** RBAC + Pundit policies (super_admin only for `/admin` routes) - [Source: ai/architecture.md#Authorization-Patterns]
- **Multi-tenancy:** All tenant tables have `company_id`, domain-based company assignment - [Source: ai/architecture.md#Multi-tenancy-Isolation]
- **Admin Panel:** Administrate gem for admin dashboards - [Source: Story 1.0]

**Technical Stack:**
- Rails 8.0.2
- PostgreSQL 15.3
- Administrate gem for admin panel
- Enumerize gem for state management
- OmniAuth + omniauth-google-oauth2 for authentication

**Database Schema:**
- `companies` table exists with: `name`, `slug`, `settings`, `state`, `created_at`, `updated_at`
- `companies` table needs new column: `email_domains` (JSONB array)
- `companies` table has branding fields: `display_name`, `logo_url`, `primary_color`, `secondary_color` - [Source: web/db/migrate/20260121010000_add_branding_to_companies.rb]
- `users` table has `company_id` (nullable, foreign key to companies)
- `users` table has `role` enumerize field (collaborator, admin, super_admin)

### Current Implementation Status

**Existing Code:**
- Company model exists at `web/app/models/company.rb` with:
  - `name`, `slug`, `state` fields
  - `has_many :users`, `has_many :projects`
  - Enumerize for `state` (active, suspended, archived)
  - Slug generation callback
  - Branding methods (`branded_name`, `branding`)
- Migration for companies exists: `web/db/migrate/20260120201006_create_companies.rb`
- Branding fields added via migration: `web/db/migrate/20260121010000_add_branding_to_companies.rb`
- `Admin::ApplicationController` exists with super_admin authentication (Story 1.0)
- `AuthConcern` exists with `authenticate_admin!` method (Story 1.0)
- Admin routes exist in `web/config/routes.rb` under `:admin` namespace
- Administrate gem is already configured and used for admin panel
- `CompanyDashboard` exists at `web/app/dashboards/company_dashboard.rb` (from Story 1.0)

**Missing Implementation:**
- `email_domains` column in companies table (needs migration)
- `initial_admin_email` field in companies (can be stored in `settings` JSONB or as separate column)
- Domain matching logic in Company model (`matches_domain?` method)
- Company assignment logic in OAuth callback
- `Admin::CompaniesController` (controller already exists from Story 1.0, but needs to be reviewed/updated)
- Controller tests for `Admin::CompaniesController`
- Integration tests for OAuth company assignment

### Previous Story Intelligence (Story 1.0)

**Key Learnings from Story 1.0:**
1. **Administrate Integration:** Admin panel uses Administrate gem, which provides standard CRUD views. Custom controllers inherit from `Administrate::ApplicationController` via `Admin::ApplicationController`.
2. **Dashboard Structure:** Each model needs a `Dashboard` class (e.g., `CompanyDashboard`) that defines `ATTRIBUTE_TYPES`, `COLLECTION_ATTRIBUTES`, `SHOW_PAGE_ATTRIBUTES`, `FORM_ATTRIBUTES`.
3. **Enumerize Fields:** For enumerize fields like `state`, use `DashboardConcern.available_states_collection` helper method to populate select options.
4. **Testing Approach:** Only controller tests are written (not model tests). Tests inherit from `Admin::ActionControllerTestCase` defined in `test_helper.rb`.
5. **Factory Pattern:** Always use FactoryBot with sequences for test data. No hardcoded values except `password_confirmation` which duplicates `password`.
6. **Super Admin Protection:** `authenticate_admin!` in `Admin::ApplicationController` ensures only super_admin can access `/admin` routes.
7. **Impersonate Functionality:** Impersonate buttons are displayed on the admin index pages for user models (from `web_reference`).

**Files Created/Modified in Story 1.0:**
- `web/app/controllers/admin/application_controller.rb` - Admin base controller
- `web/app/controllers/concerns/auth_concern.rb` - Added `authenticate_admin!`, `impersonate_user`, `stop_impersonating_user`
- `web/app/dashboards/user_dashboard.rb` - Administrate dashboard for User model
- `web/app/dashboards/company_dashboard.rb` - Administrate dashboard for Company model (already exists!)
- `web/app/dashboards/concerns/dashboard_concern.rb` - Helper methods for enumerize fields
- `web/config/routes.rb` - Admin namespace with resources (users, companies, projects, project_collaborators)
- `web/test/controllers/admin/users_controller_test.rb` - Controller tests for UsersController
- `web/test/controllers/admin/companies_controller_test.rb` - Controller tests for CompaniesController (already exists!)

**Code Patterns from Story 1.0:**
- Enumerize usage: `enumerize :state, in: %i[active suspended archived], default: :active, predicates: true, scope: true`
- Dashboard field for enumerize: `state: Field::Select.with_options(include_blank: false, collection: ->(field) { available_states_collection(field, :state) })`
- Controller test setup: `@super_admin = create(:user, :super_admin); sign_in @super_admin`
- Factory traits: `:super_admin`, `:admin_role`, `:collaborator`, `:with_company`

### Project Structure Notes

**Files to Create/Modify:**
- `web/db/migrate/YYYYMMDDHHMMSS_add_email_domains_to_companies.rb` - Add email_domains and initial_admin_email fields
- `web/app/models/company.rb` - Add domain matching logic and validations
- `web/app/controllers/admin/companies_controller.rb` - CRUD controller for companies (may already exist, verify)
- `web/app/dashboards/company_dashboard.rb` - Update dashboard to include new fields (already exists from Story 1.0)
- `web/app/controllers/api/v1/sessions_controller.rb` (or OAuth callback controller) - Add company assignment logic
- `web/config/routes.rb` - Verify companies resource in admin namespace (likely already there)
- `web/test/controllers/admin/companies_controller_test.rb` - Controller tests (may already exist from Story 1.0)
- `web/test/integration/oauth_company_assignment_test.rb` - Integration tests for OAuth flow
- `web/test/factories/users.rb` - Add `:matches_domain` trait
- `web/test/factories/companies.rb` - Ensure company factory supports email_domains

**Database Schema Changes:**
- Add `email_domains` column to `companies` table (JSONB, nullable, default: `[]`)
- Add `initial_admin_email` column to `companies` table (string, nullable) OR store in `settings` JSONB
- Consider adding index on `email_domains` for faster domain lookup (GIN index for JSONB)

### Technical Specifications

**Email Domain Matching:**
- **Storage:** `email_domains` as JSONB array - `["example.com", "subsidiary.com"]`
- **Validation:** Each domain must be a valid domain format (regex: `/\A[a-z0-9-]+\.[a-z]{2,}\z/i`)
- **Matching Logic:** Extract domain from email (`email.split('@').last`) and check if it's in `email_domains` array
- **Multiple Matches:** If multiple companies match the domain, choose the first one (or implement priority/precedence logic)
- **No Match:** If no company matches, either:
  - Option A: Leave `company_id` as nil (user can't access platform until assigned)
  - Option B: Create a default "Unassigned" company
  - **Decision:** Option A for MVP (more secure, requires explicit assignment)

**Initial Admin Email:**
- **Storage:** `initial_admin_email` as string column OR in `settings` JSONB
- **Purpose:** When a user signs in with this email, they are automatically assigned `admin` role (instead of default `collaborator`)
- **Validation:** Must be a valid email format
- **Behavior:** Only applies on first sign-in. If user already exists, role is NOT changed.

**Company State Management:**
- **States:** `active`, `suspended`, `archived` (via enumerize)
- **Suspended State:** Users cannot sign in or access platform (enforce in `AuthConcern`)
- **Archived State:** Company is soft-deleted, users cannot sign in
- **Enforcement:** Check company state in authentication flow

**OAuth Company Assignment Flow:**
1. User completes Google OAuth successfully
2. Extract email from OAuth response (e.g., `auth.info.email`)
3. Extract domain from email: `email.split('@').last`
4. Search for company with matching domain: `Company.active.find { |c| c.matches_domain?(email) }`
5. If company found:
   - Assign `company_id` to user
   - If email matches `initial_admin_email`, assign `role = 'admin'`
   - Otherwise assign `role = 'collaborator'` (default)
6. If no company found:
   - Leave `company_id` as nil
   - User will see error message and cannot access platform
7. Save user and proceed with session creation

### Testing Requirements

**Controller Tests (Admin::CompaniesController):**
- **Setup:** Create super_admin user, sign in via `sign_in @super_admin`
- **Test Index:** Verify super admin can view companies list with user counts
- **Test New:** Verify super admin can view new company form
- **Test Create:** Verify super admin can create company with email_domains and initial_admin_email
- **Test Show:** Verify super admin can view company details including users association
- **Test Edit:** Verify super admin can view edit form
- **Test Update:** Verify super admin can update company fields (name, domains, state, branding)
- **Test Destroy:** Verify super admin can delete company (with dependent: :destroy cascade)
- **Test Access Control:** Verify non-super-admin users (admin, collaborator, unauthenticated) are denied access

**Integration Tests (OAuth Company Assignment):**
- **Setup:** Create company with email domain "example.com"
- **Test Domain Match:** User signs in with "user@example.com" → assigned to company
- **Test Initial Admin:** Company has initial_admin_email "admin@example.com", user signs in → assigned `admin` role
- **Test Default Role:** User signs in without matching initial_admin_email → assigned `collaborator` role
- **Test No Match:** User signs in with non-matching domain → `company_id` remains nil
- **Test Existing User:** User signs in again → company_id and role remain unchanged (idempotent)

**Factory Updates:**
- **Company Factory:** Add `email_domains` as `["example.com"]` by default (or use sequence)
- **Company Factory Trait:** `:with_multiple_domains` → `email_domains: ["example.com", "subsidiary.com"]`
- **Company Factory Trait:** `:with_initial_admin` → `initial_admin_email: generate(:email)`
- **User Factory Trait:** `:matches_domain` → email generated to match a company's domain

### API & Data Flow

**Admin Panel Flow:**
1. Super admin navigates to `/admin` → redirected to `/admin/users` (current root) or `/admin/companies` (proposed)
2. Super admin clicks "Companies" in admin nav → `/admin/companies` (index)
3. Index page shows: company name, slug, domains (comma-separated), user count, state, actions (show, edit, delete)
4. Super admin clicks "New Company" → `/admin/companies/new`
5. Form fields: name, email_domains (text area, comma-separated), initial_admin_email, state, branding fields
6. Submit → POST `/admin/companies` → company created → redirect to `/admin/companies/:id`
7. Show page displays all company details + list of users (via Administrate has_many field)
8. Edit → `/admin/companies/:id/edit` → update fields → PATCH `/admin/companies/:id` → redirect to show
9. Delete → `/admin/companies/:id` → confirm dialog → DELETE `/admin/companies/:id` → redirect to index

**OAuth Company Assignment Flow:**
1. User clicks "Sign in with Google" → redirected to Google OAuth
2. User authorizes → Google redirects to callback URL (e.g., `/auth/google_oauth2/callback`)
3. Callback controller receives OAuth response with user info (email, name, etc.)
4. Controller extracts email domain and searches for matching company
5. If company found:
   - Create or update User record with `company_id`, `role` (admin or collaborator)
   - Create session for user
   - Redirect to dashboard
6. If no company found:
   - Create User record with `company_id = nil`, `role = 'collaborator'`
   - Show error message: "Your email domain is not registered. Contact your administrator."
   - Redirect to login page (user cannot access platform)

### Security & Error Handling

**Security Considerations:**
- **Super Admin Only:** All `/admin/companies` routes protected by `authenticate_admin!` (checks `true_user.super_admin?`)
- **Company State Enforcement:** Check company state in `AuthConcern` before allowing sign in
- **Domain Validation:** Ensure email_domains contain only valid domain formats (prevent injection)
- **Deletion Safeguards:** Show confirmation dialog with warning about data loss before deleting company

**Error Handling:**
- **Invalid Email Domains:** Show validation error: "Email domains must be valid domain formats (e.g., example.com)"
- **Duplicate Company Name:** Show validation error: "Company name has already been taken"
- **OAuth No Company Match:** Show error message: "Your email domain (@example.com) is not registered. Contact your administrator."
- **Suspended/Archived Company:** Show error message: "Your company account is suspended. Contact support."

### References

- [Source: ai/epics.md#Story-1.1] - Story 1.1 detailed acceptance criteria
- [Source: ai/architecture.md#Authentication--Security] - Authentication and authorization patterns
- [Source: ai/architecture.md#Multi-tenancy-Isolation] - Multi-tenancy and company_id filtering
- [Source: web/app/models/company.rb] - Existing Company model structure
- [Source: web/db/migrate/20260120201006_create_companies.rb] - Companies table schema
- [Source: web/db/migrate/20260121010000_add_branding_to_companies.rb] - Branding fields
- [Source: _bmad-output/implementation-artifacts/1-0-initial-super-admin-setup.md] - Previous story (Story 1.0) learnings
- [Source: web/app/dashboards/company_dashboard.rb] - Existing CompanyDashboard from Story 1.0
- [Source: web/test/controllers/admin/companies_controller_test.rb] - Existing controller tests from Story 1.0

## Dev Agent Record

### Agent Model Used

(To be filled by dev agent)

### Debug Log References

(To be filled by dev agent)

### Completion Notes List

(To be filled by dev agent)

### File List

**To be Created:**
- `web/db/migrate/YYYYMMDDHHMMSS_add_email_domains_to_companies.rb` - Migration for email_domains and initial_admin_email
- `web/test/integration/oauth_company_assignment_test.rb` - Integration tests for OAuth company assignment

**To be Modified:**
- `web/app/models/company.rb` - Add email_domains validation and domain matching logic
- `web/app/dashboards/company_dashboard.rb` - Update to include email_domains and initial_admin_email fields
- `web/app/controllers/api/v1/sessions_controller.rb` (or OAuth callback controller) - Add company assignment logic
- `web/app/controllers/admin/companies_controller.rb` - Verify CRUD implementation (may already exist from Story 1.0)
- `web/test/controllers/admin/companies_controller_test.rb` - Add tests for email_domains and initial_admin_email (may already exist)
- `web/test/factories/users.rb` - Add `:matches_domain` trait
- `web/test/factories/companies.rb` - Add email_domains field
