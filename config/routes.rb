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

  # API routes
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      get "auth/:provider", to: redirect("/api/v1/auth/%{provider}"), as: :auth, format: :html
      get "auth/:provider/callback", to: "sessions#omniauth", as: :auth_callback, format: :html
      get "auth/failure", to: "sessions#failure", as: :auth_failure, format: :html

      resource :sessions, only: %i[create destroy]
      resource :current_user, only: %i[show update], controller: "current_user"

      resources :agent_models, only: [:index], controller: "agent_models" do
        put :update_default, on: :collection
      end
      resources :contact_requests, only: %i[create]

      resources :assets, only: [], controller: "assets" do
        collection do
          get :presign
          post :upload
        end
      end
      resources :terminal_sessions, only: %i[index show create update destroy] do
        member do
          post :finish
        end
      end

      namespace :internal do
        get "ws_auth", to: "ws_auth#show"
        post "usage_statistics", to: "usage_statistics#create"
      end

      namespace :company do
        resources :integrations, only: %i[index show create destroy] do
          collection do
            get :github_setup, defaults: { format: :html }
          end
        end
        resources :users, only: %i[index create update destroy]
        resources :config_items, only: %i[index create update destroy]
        resources :agents, only: %i[index create update destroy]
        resources :tools, only: %i[index create update destroy]
        resources :mcp_servers, only: %i[index create update destroy]
        resources :skills, only: %i[index create update destroy]
        resources :workflows, only: %i[index show create update destroy] do
          scope module: :workflows do
            resources :steps, only: %i[index show create update destroy] do
              collection do
                patch :reorder
              end
            end
          end
        end
        resources :repositories, only: %i[index show create update destroy] do
          collection do
            get :available
            get :branches
          end
        end
        resources :assets, only: %i[index show create update destroy] do
          member do
            get :download
            get :versions
            post :restore
          end
        end
        resources :terminal_sessions, only: %i[index show] do
          scope module: :terminal_sessions do
            resources :artifacts, only: [ :index ] do
              collection do
                post :review
              end
              member do
                get :download
              end
            end
          end
        end
        resources :projects, only: %i[index show create update] do
          scope module: :projects do
            resources :collaborators, only: %i[index create destroy]
            resources :config_items, only: %i[index create update destroy]
            resources :agents, only: %i[index create update destroy]
            resources :tools, only: %i[index create update destroy]
            resources :mcp_servers, only: %i[index create update destroy]
            resources :integrations, only: %i[index create destroy]
            resources :skills, only: %i[index create update destroy]
            resources :workflows, only: %i[index show create update destroy] do
              member do
                post :duplicate
              end
              scope module: :workflows do
                resources :steps, only: %i[index show create update destroy] do
                  collection do
                    patch :reorder
                  end
                end
              end
            end
            resources :repositories, only: %i[index create update destroy] do
              collection do
                get :available
                get :branches
              end
            end
            resources :assets, only: %i[index show create update destroy] do
              member do
                get :download
                get :versions
                post :restore
              end
            end
            resource :board, only: %i[show create update destroy] do
              collection do
                get :presets
              end
              resources :columns, controller: "board/columns" do
                collection do
                  patch :reorder
                end
                resource :workflow_binding, controller: "board/columns/workflow_binding", only: %i[show create update destroy]
              end
              resources :activities, controller: "board/activities", only: %i[index]
              resources :view_presets, controller: "board/view_presets", only: %i[index create destroy]
              resources :tasks, controller: "board/tasks" do
                member do
                  patch :move
                  post :trigger_workflow
                  get :workflow_runs
                end
                resources :comments, controller: "board/task/comments", only: %i[index create]
                resources :assets, controller: "board/task/assets", only: %i[index create destroy]
                resources :waits, controller: "board/task/waits", only: %i[destroy]
                resources :transitions, controller: "board/task/transitions", only: %i[index]
                resources :activities, controller: "board/task/activities", only: %i[index]
                resource :statistics, controller: "board/task/statistics", only: %i[show]
              end
            end
            namespace :statistic do
              resource :analytics, only: %i[show], controller: "analytics" do
                member do
                  get :agent_activity
                  get :session_source_breakdown
                  get :session_duration_distribution
                  get :cost_token_usage
                  get :filter_options
                end
              end
              resource :workflow_costs, only: %i[show], controller: "workflow_costs"
              resource :overview, only: %i[show], controller: "overview"
              resource :recent_activity, only: %i[show], controller: "recent_activity"
              resource :workflow_runs, only: %i[show], controller: "workflow_runs"
              resource :board_task_distribution, only: %i[show], controller: "board_task_distribution"
            end
            resources :terminal_sessions, only: %i[index show]
            resources :workflow_runs, only: %i[index show create] do
              member do
                post :approve_step
                post :retry_step
                post :skip_step
                post :cancel
              end
              resources :workflow_run_assets, only: %i[index], path: "assets" do
                member do
                  post :export
                  get :download
                end
                collection do
                  post :export_all
                end
              end
            end
          end
        end
      end
    end
  end

  namespace :admin do
    root to: "users#index"

    resources :agent_models, only: [:index]

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
    resources :contact_requests, only: %i[index show destroy]

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
    mount OasRails::Engine => "/docs"
    mount(LetterOpenerWeb::Engine, at: "/letter_opener") if Rails.env.development?

    get "privacy-policy", to: "pages#privacy_policy", as: :privacy_policy
    get "terms-of-service", to: "pages#terms_of_service", as: :terms_of_service

    get "*path", to: "home#show"
  end
end
