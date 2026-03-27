# Story 16.5: Artifact Review API

Status: ready-for-dev

## Story

As a user,
I want an API to view pending session outputs and make keep/dismiss decisions,
so that I control which outputs become permanent project assets.

## Acceptance Criteria

1. **AC1: Index endpoint** — `GET /api/v1/company/terminal_sessions/:terminal_session_id/artifacts` returns pending-review assets for the session. Includes: id, name, folder, file_size, content_type, download_url, created_at. Sorted by name.

2. **AC2: Review endpoint** — `POST /api/v1/company/terminal_sessions/:terminal_session_id/artifacts/review` accepts `{ decisions: { "<asset_id>": "save" | "dismiss" }, target_scope_type: "Project" | "Company", target_scope_id: <id> }`. Processes each decision and marks session as `artifacts_reviewed: true`.

3. **AC3: Save logic** — For `"save"`: updates asset `status: "active"`, `reviewed_at: Time.current`, `scope_type: target_scope_type`, `scope_id: target_scope_id`, `folder: nil` (moves out of session folder).

4. **AC4: Dismiss logic** — For `"dismiss"`: updates asset `status: "dismissed"`, `reviewed_at: Time.current`.

5. **AC5: Authorization** — User must own the session or be admin of the company. Target scope must be accessible.

6. **AC6: Routes** — Properly nested under `terminal_sessions`.

## Tasks / Subtasks

- [ ] Task 1: Create ArtifactsController (AC: #1, #2, #3, #4)
  - [ ] 1.1 Create `web/app/controllers/api/v1/company/terminal_sessions/artifacts_controller.rb`
  - [ ] 1.2 Implement `index` action: load session, return `output_assets.pending_review`
  - [ ] 1.3 Implement `review` action: process decisions hash, update assets, mark session reviewed
  - [ ] 1.4 Add `download` action for individual file download (reuse AssetVersion download pattern)
- [ ] Task 2: Add routes (AC: #6)
  - [ ] 2.1 In `config/routes.rb`, nest artifacts under company terminal_sessions
- [ ] Task 3: Create serializer
  - [ ] 3.1 Create `SessionArtifactSerializer` (or reuse `AssetSerializer` with conditional fields)
- [ ] Task 4: Create policy (AC: #5)
  - [ ] 4.1 Create `Api::V1::Company::TerminalSessions::ArtifactsPolicy`
  - [ ] 4.2 index/review: session owner or company admin
  - [ ] 4.3 Validate target_scope accessibility
- [ ] Task 5: Write tests
  - [ ] 5.1 Controller test: index returns pending assets
  - [ ] 5.2 Controller test: review saves/dismisses correctly
  - [ ] 5.3 Controller test: authorization checks
  - [ ] 5.4 Controller test: marks session as artifacts_reviewed

## Dev Notes

### Controller Structure

Follow existing nested controller pattern (see `Api::V1::Company::Projects::AssetsController`).

```ruby
module Api
  module V1
    module Company
      module TerminalSessions
        class ArtifactsController < ApplicationController
          before_action :set_session

          def index
            artifacts = @session.output_assets.pending_review.order(:name)
            respond_with artifacts, each_serializer: SessionArtifactSerializer
          end

          def review
            decisions = params.require(:decisions).to_unsafe_h
            target_scope_type = params[:target_scope_type]
            target_scope_id = params[:target_scope_id]

            validate_target_scope!(target_scope_type, target_scope_id)

            ActiveRecord::Base.transaction do
              decisions.each do |asset_id, decision|
                asset = @session.output_assets.find(asset_id)
                case decision
                when "save"
                  asset.update!(
                    status: "active",
                    reviewed_at: Time.current,
                    scope_type: target_scope_type,
                    scope_id: target_scope_id,
                    folder: nil
                  )
                when "dismiss"
                  asset.update!(
                    status: "dismissed",
                    reviewed_at: Time.current
                  )
                end
              end
              @session.update!(artifacts_reviewed: true)
            end

            respond_with @session, serializer: TerminalSessionSerializer
          end

          def download
            asset = @session.output_assets.find(params[:id])
            version = asset.latest_version
            raise ActiveRecord::RecordNotFound, "No file version" unless version

            redirect_to version.file_url(
              response_content_disposition: ::ContentDisposition.attachment(asset.name)
            ), allow_other_host: true
          end

          private

          def set_session
            @session = current_company.terminal_sessions.find(params[:terminal_session_id])
          end

          def validate_target_scope!(scope_type, scope_id)
            return unless scope_type.present? && scope_id.present?

            case scope_type
            when "Project"
              project = current_company.projects.find(scope_id)
              raise Pundit::NotAuthorizedError unless project.accessible_by?(current_user)
            when "Company"
              raise Pundit::NotAuthorizedError unless scope_id.to_i == current_company.id
            else
              raise ArgumentError, "Invalid scope_type"
            end
          end
        end
      end
    end
  end
end
```

### Routes

Add to `config/routes.rb` inside the `namespace :company` block:

```ruby
resources :terminal_sessions, only: %i[index show] do
  scope module: :terminal_sessions do
    resources :artifacts, only: [:index] do
      collection do
        post :review
      end
      member do
        get :download
      end
    end
  end
end
```

### Serializer

```ruby
class SessionArtifactSerializer < ApplicationSerializer
  attributes :id, :name, :folder, :status, :file_size, :content_type, :download_url, :created_at

  def file_size
    object.latest_version&.file_size
  end

  def content_type
    object.latest_version&.content_type
  end

  def download_url
    version = object.latest_version
    return nil unless version&.file.present?

    version.file_url(
      response_content_disposition: ::ContentDisposition.attachment(object.name)
    )
  end
end
```

### current_company Helper

Existing `ApplicationController` provides `current_company` via `current_user.company`. Terminal sessions are found via `current_company.terminal_sessions` — but `TerminalSession` doesn't have a direct `company` association. Need to find via user:

```ruby
def set_session
  @session = TerminalSession.joins(:user)
    .where(users: { company_id: current_company.id })
    .find(params[:terminal_session_id])
end
```

Or simpler, if the existing pattern allows:
```ruby
def set_session
  @session = TerminalSession.find(params[:terminal_session_id])
  raise Pundit::NotAuthorizedError unless @session.user.company_id == current_company.id
end
```

### Files to Touch

- `web/app/controllers/api/v1/company/terminal_sessions/artifacts_controller.rb` (new)
- `web/app/serializers/session_artifact_serializer.rb` (new)
- `web/app/policies/api/v1/company/terminal_sessions/artifacts_policy.rb` (new)
- `web/config/routes.rb` — add nested artifacts routes
- `web/test/controllers/api/v1/company/terminal_sessions/artifacts_controller_test.rb` (new)

### Dependencies

- **Requires Story 16.4** — Assets have `status`, `terminal_session_id`, `reviewed_at` columns

### References

- [Source: ai/epics/epic-16-session-outputs-and-config-normalization.md#Story 16.5]
- [Source: web/app/controllers/api/v1/company/assets_controller.rb — download pattern]
- [Source: web/app/controllers/api/v1/company/projects/assets_controller.rb — nested controller pattern]
- [Source: web/config/routes.rb — existing terminal_sessions routes]
- [Source: web/app/policies/api/v1/company/terminal_sessions_policy.rb — existing policy]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
