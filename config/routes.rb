Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # ActionCable WebSocket endpoint
  mount ActionCable.server => "/cable"

  # ActionMCP server endpoint (Model Context Protocol for agent containers)
  mount ActionMCP::Engine => "/action_mcp"

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

    get "privacy-policy", to: "pages#privacy_policy", as: :privacy_policy
    get "terms-of-service", to: "pages#terms_of_service", as: :terms_of_service

    resource :profile, only: %i[show update], controller: "profile" do
      put :update_default_model, on: :member
      delete :destroy_credential, on: :member
    end
    resource :onboarding, only: %i[show update], controller: "onboarding"

    # Slack OAuth callback — one deployment-wide redirect URI registered on the
    # Slack app; the project is carried in the signed `state`, not the path.
    get "integrations/slack/oauth/callback", to: "integrations/slack_oauth#callback", as: :slack_oauth_callback

    namespace :company do
      resources :members, only: %i[index create update destroy]
      resources :config_items, only: %i[index create update destroy]
      # GitHub App setup callback (single global endpoint; project target carried in `state`).
      # Company-level integration management has been removed — integrations are project-scoped.
      get "integrations/github_setup", to: "integrations/github_setup#github_setup",
          as: :integrations_github_setup
      resources :projects, only: %i[index show create destroy] do
        scope module: :projects do
          resources :overview, only: :index
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
          resources :integrations, only: %i[index create destroy] do
            collection do
              get :slack_oauth_start
            end
          end
          resources :agents, only: %i[index create update destroy]
          resources :tools, only: %i[index create update destroy]
          resources :mcp_servers, only: %i[index create update destroy]
          resources :skills, only: %i[index create destroy]
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
