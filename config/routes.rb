Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"

  namespace :api do
    namespace :v1 do
      # Campaign endpoints
      resources :campaigns, param: :campaign_guid, only: [ :show ] do
        member do
          get :results
        end
      end

      # Push test endpoint
      post "push_test", to: "push_test#send_test"

      # Health check endpoint
      get "health", to: "health#show"

      get "push_retries/stats", to: "push_retries#stats"
      delete "push_retries", to: "push_retries#cancel"
    end
  end
end
