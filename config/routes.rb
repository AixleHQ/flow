Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # ActionCable WebSocket endpoint
  mount ActionCable.server => "/cable"

  # ActionMCP server endpoint (Model Context Protocol for agent containers)
  mount ActionMCP::Engine => "/action_mcp"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # API routes
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      get "auth/:provider", to: redirect("/api/v1/auth/%{provider}"), as: :auth, format: :html
      get "auth/:provider/callback", to: "sessions#omniauth", as: :auth_callback, format: :html
      get "auth/failure", to: "sessions#failure", as: :auth_failure, format: :html

      resource :sessions, only: %i[create destroy]
      resource :current_user, only: %i[show update], controller: "current_user"

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
        resources :projects, only: %i[index show create] do
          scope module: :projects do
            resources :collaborators, only: %i[index create destroy]
            resources :config_items, only: %i[index create update destroy]
            resources :agents, only: %i[index create update destroy]
            resources :tools, only: %i[index create update destroy]
            resources :mcp_servers, only: %i[index create update destroy]
            resources :skills, only: %i[index create update destroy]
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
            resources :terminal_sessions, only: %i[index show]
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
  end

  scope module: :web, defaults: { format: :html } do
    root "home#show"
    mount OasRails::Engine => "/docs"
    mount(LetterOpenerWeb::Engine, at: "/letter_opener") if Rails.env.development?

    get "*path", to: "home#show"
  end
end
