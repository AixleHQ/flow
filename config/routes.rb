Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # ActionCable WebSocket endpoint
  mount ActionCable.server => "/cable"

  # Aixle MCP server endpoint (Model Context Protocol for agent containers).
  # /action_mcp is the legacy path agent containers are configured with
  # (Settings.mcp.server_url); /mcp is the forward-looking alias.
  match "/action_mcp", to: "mcp#handle", via: %i[get post delete]
  match "/mcp", to: "mcp#handle", via: %i[get post delete]

  # Credential vending for agent containers (Amazon Bedrock and friends). Called by the
  # in-container credential_process helper, authenticated by a derived per-session key
  # rather than a user session — see CloudAuth::SessionKey.
  post "/cloud/aws/credentials", to: "cloud_credentials#create"

  # CSP violation report sink (report-only mode, M-16). Browsers POST here with
  # Content-Type application/csp-report; no session/CSRF token is sent.
  post "/csp-violation-report-endpoint", to: "csp_reports#create"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # GitHub webhook endpoint (public, no session auth — verified via HMAC signature)
  post "/webhooks/github", to: "webhooks/github#receive"

  # GitLab webhook endpoint (public, no session auth — verified via per-repository secret)
  post "/webhooks/gitlab", to: "webhooks/gitlab#receive"

  # Generic inbound webhook gateway (arbitrary sources, public — verified
  # per-endpoint via WebhookEndpoint#verification_strategy on the raw body).
  post "/webhooks/in/:slug", to: "webhooks/ingress#receive", as: :webhook_ingress

  # Multi-workspace Slack Events API endpoint (public — verified centrally with
  # the app signing secret, then routed by team_id to the workspace's install).
  post "/webhooks/slack/events", to: "webhooks/slack#events", as: :slack_events_webhook

  # Public asset share links (no session auth — reachable by anyone with the
  # token). The viewer renders the asset inside a sandboxed iframe; the token
  # lives on the asset so the URL is stable across versions.
  get "/share/:token", to: "web/public_assets#show", as: :public_asset
  get "/share/:token/raw", to: "web/public_assets#raw", as: :public_asset_raw

  # OmniAuth callbacks (path_prefix = /auth)
  get "auth/:provider/callback", to: "web/sessions#omniauth", as: :auth_callback
  get "auth/failure", to: "web/sessions#failure", as: :auth_failure

  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      resources :assets, only: [] do
        collection do
          get :presign
          post :upload
        end
      end

      namespace :internal do
        get "ws_auth", to: "ws_auth#show"
        post "usage_statistics", to: "usage_statistics#create"
      end

      resources :terminal_sessions, only: %i[show create destroy] do
        member do
          post :finish
          get :terminal_log
        end
      end

      # Cloud-provider connections (Amazon Bedrock via IAM Identity Center). One per
      # user, driven from the browser: create → poll → complete.
      namespace :cloud do
        resource :aws_connection, only: %i[show create destroy], controller: "aws_connections" do
          post :poll
          post :complete
          # Vends credentials and invokes a model, because Claude Code hides Bedrock
          # errors and this is the only way a user sees why their connection fails.
          post :health
        end
      end

      namespace :company do
        resources :assets, only: %i[create destroy] do
          member do
            get :download
          end
        end
      end

      resources :projects, only: [] do
        scope module: :projects do
          resources :assets, only: %i[create destroy] do
            member do
              get :download
            end
          end

          resources :workflows, only: %i[show update destroy] do
            scope module: :workflows do
              resources :steps, only: %i[index show create update destroy] do
                collection do
                  patch :reorder
                end
              end
              resources :triggers, only: %i[index create update destroy]
            end
          end

          resources :workflow_runs, only: [] do
            resources :workflow_run_assets, only: %i[index] do
              member do
                post :export
                get :download
              end
              collection do
                post :export_all
              end
            end
          end

          resource :board, only: %i[create update destroy], controller: "board"
          scope module: :board do
            resources :view_presets, only: %i[index create destroy]
            resources :columns do
              collection do
                patch :reorder
              end
              scope module: :columns do
                resource :workflow_binding, only: %i[show create update destroy]
              end
            end
            resources :activities, only: %i[index]
            resources :tasks do
              member do
                patch :move
                patch :archive
                patch :unarchive
                post :trigger_workflow
                get :workflow_runs
              end
              scope module: :task do
                resources :comments, only: %i[index create]
                resources :assets, only: %i[index create destroy]
                resources :gates, only: %i[destroy]
                resources :transitions, only: %i[index]
                resources :activities, only: %i[index]
                resource :statistics, only: %i[show]
              end
            end
          end
        end
      end
    end
  end

  namespace :admin do
    root to: "users#index"

    resources :users do
      member do
        post :impersonate
        post :stop_impersonate
      end
    end
    resources :companies
    resources :projects
    resources :project_collaborators
    resources :agent_credentials
    resources :terminal_sessions, only: %i[index show]
    resources :session_logs, only: %i[index show]
    resources :assets, only: %i[index show]
    resources :asset_versions, only: %i[index show]
    resources :tool_results, only: %i[index show]

    resources :agents, only: %i[index show]
    resources :boards, only: %i[index show]
    resources :board_activities, only: %i[index show]
    resources :board_columns, only: %i[index show]
    resources :board_tasks, only: %i[index show]
    resources :board_view_presets, only: %i[index show]
    resources :column_transitions, only: %i[index show]
    resources :column_workflow_bindings, only: %i[index show]
    resources :config_items, only: %i[index show]
    resources :integrations, only: %i[index show]
    resources :mcp_servers, only: %i[index show]
    resources :oauth_clients, only: %i[index show]
    resources :oauth_credentials, only: %i[index show]
    resources :repositories, only: %i[index show]
    resources :skills, only: %i[index show]
    resources :tools, only: %i[index show]
    resources :tool_files, only: %i[index show]
    resources :workflows, only: %i[index show]
    resources :workflow_runs, only: %i[index show]
    resources :workflow_run_assets, only: %i[index show]
    resources :steps, only: %i[index show]
    resources :step_runs, only: %i[index show]
    resources :sub_steps, only: %i[index show]
    resources :sub_step_runs, only: %i[index show]
    resources :task_comments, only: %i[index show]
    resources :task_assets, only: %i[index show]
    resources :usage_statistics, only: %i[index show]
    resources :namespace_resource_quotas
    # Not an Administrate resource: manual triggers for the mirrored catalogs, so a
    # fresh deployment does not sit on an empty catalog until the first scheduled run.
    resources :catalog_syncs, only: %i[index create]
  end

  scope module: :web, defaults: { format: :html } do
    root "home#show"
    mount OasRails::Engine => "/api-docs"
    mount(LetterOpenerWeb::Engine, at: "/letter_opener") if Rails.env.development?

    get "docs", to: "docs#show", as: :docs
    get "docs/*slug", to: "docs#show", as: :docs_page, constraints: { slug: /[^\/]+/ }

    get "login", to: "sessions#new", as: :login
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy", as: :logout

    # Invitation acceptance (public — the signed token is the credential).
    # Tokens can contain dots, which format negotiation would otherwise eat.
    scope constraints: { token: /[^\/]+/ } do
      get "invitations/:token", to: "invitations#show", as: :invitation
      post "invitations/:token/accept", to: "invitations#accept", as: :accept_invitation
      post "invitations/:token/decline", to: "invitations#decline", as: :decline_invitation
      post "invitations/:token/signup", to: "invitations#signup", as: :signup_invitation
    end

    get "privacy-policy", to: "pages#privacy_policy", as: :privacy_policy
    get "terms-of-service", to: "pages#terms_of_service", as: :terms_of_service

    resource :profile, only: %i[show update], controller: "profile" do
      get :usage, on: :member
      put :update_default_model, on: :member
      delete :destroy_credential, on: :member
      post :regenerate_mcp_token, on: :member
      delete :disable_mcp_token, on: :member
    end
    resource :onboarding, only: %i[show update], controller: "onboarding"

    # Slack OAuth callback — one deployment-wide redirect URI registered on the
    # Slack app; the project is carried in the signed `state`, not the path.
    get "integrations/slack/oauth/callback", to: "integrations/slack_oauth#callback", as: :slack_oauth_callback

    # Unified OAuth (RFC oauth-unification §4.2). One deployment-wide callback for
    # every provider; the provider + all routing data are carried in a signed,
    # single-use `state`. PKCE is mandatory (OAuth 2.1).
    # Public RFC "Client ID Metadata Document" (CIMD). When an MCP authorization
    # server supports CIMD, this URL is our client_id and the AS dereferences it.
    get "oauth/client-metadata.json", to: "oauth#client_metadata", as: :oauth_client_metadata
    get "oauth/:provider/authorize", to: "oauth#authorize", as: :oauth_authorize
    get "oauth/callback", to: "oauth#callback", as: :oauth_callback
    # MCP OAuth 2.1 connect (oauth-unification §5): discovery + dynamic client
    # registration, then the SAME consent flow as #authorize. The mcp_server_id
    # sources the discovered DCR client; the callback stays the shared oauth_callback.
    get "oauth/mcp/:mcp_server_id/connect", to: "oauth#mcp_connect", as: :oauth_mcp_connect

    namespace :company do
      post "switch", to: "switch#create", as: :switch
      # Self-removal ("Leave company" on the profile page) — id is the
      # MEMBERSHIP id, and it may belong to any of the user's companies.
      resources :memberships, only: %i[destroy]
      resources :members, only: %i[index create update destroy] do
        post :resend, on: :member
      end
      # Config items are Project-scoped only — managed under company/projects/:id/config_items.
      # GitHub App setup callback (single global endpoint; project target carried in `state`).
      # Company-level integration management has been removed — integrations are project-scoped.
      get "integrations/github_setup", to: "integrations/github_setup#github_setup",
          as: :integrations_github_setup
      resources :projects, only: %i[index show create destroy] do
        scope module: :projects do
          resources :overview, only: :index
          # Per-user star on the project tiles. Singular: there is at most one
          # favorite per (user, project), and the actor is always current_user.
          resource :favorite, only: %i[create destroy]
          resource :board, only: %i[show]
          resources :sessions, only: %i[index new show] do
            scope module: :sessions do
              resources :artifacts, only: :index do
                collection do
                  post :review
                end
              end
            end
          end
          resources :workflows, only: %i[index create destroy] do
            member do
              get :builder
              post :publish
              post :unpublish
              post :duplicate
            end
          end
          resources :workflow_runs, only: %i[index show create] do
            member do
              post :cancel
              post :approve_step
              post :retry_step
              post :skip_step
            end
          end
          get "aixle_builder", to: "aixle_builder#show", as: :aixle_builder
          post "aixle_builder/start", to: "aixle_builder#start", as: :aixle_builder_start
          get "aixle_builder/:id/session", to: "aixle_builder#show_session", as: :aixle_builder_session
          post "aixle_builder/:id/finish", to: "aixle_builder#finish", as: :aixle_builder_finish
          resources :assets, only: %i[index]
          resources :analytics, only: :index
          resources :repositories, only: %i[index create update destroy]
          # `update` edits provider settings only (Coder's template / prefix /
          # lock TTL) — credentials are replaced by reconnecting, which has to
          # re-verify them against the provider.
          resources :integrations, only: %i[index create update destroy] do
            collection do
              get :slack_oauth_start
              get :github_app_install
            end
          end
          resources :agents, only: %i[index create update destroy]
          resources :tools, only: %i[index create update destroy]
          resources :mcp_servers, only: %i[index create update destroy] do
            member do
              post :accept_tool_drift
              post :update_connector
            end
          end
          resources :connectors, only: %i[create]
          # `update` edits a hand-written skill only; a registry skill is upstream's
          # content and editing it would silently diverge from the source it names.
          resources :skills, only: %i[index create update destroy] do
            collection do
              # Registering a hand-written SKILL.md, as opposed to installing a
              # registry entry by id — different input, different validation.
              post :manual
            end
          end
          resources :config_items, only: %i[index create update destroy]
          resources :members, only: %i[index create destroy]
          resource :settings, only: %i[show update]
        end
      end
      resources :workflow_catalog, only: :index do
        member do
          post :duplicate
        end
      end
      resources :analytics, only: :index
      resources :assets, only: %i[index]
      resources :sessions, only: %i[index show] do
        scope module: :sessions do
          resources :artifacts, only: :index do
            collection do
              post :review
            end
          end
        end
      end
    end
  end
end
