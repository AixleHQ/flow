Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # ActionCable WebSocket endpoint
  mount ActionCable.server => "/cable"

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
      resources :terminal_sessions, only: %i[index show create update destroy] do
        member do
          post :finish_auth
          post :cancel
        end
      end

      namespace :internal do
        get "ws_auth", to: "ws_auth#show"
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
  end

  scope module: :web, defaults: { format: :html } do
    root "home#show"
    mount OasRails::Engine => "/docs"
    mount(LetterOpenerWeb::Engine, at: "/letter_opener") if Rails.env.development?

    get "*path", to: "home#show"
  end
end
