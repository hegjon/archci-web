Rails.application.routes.draw do
  root "farm#show"
  resources :jobs, only: %i[index show], constraints: { id: %r{[^/]+} }, format: false do
    member do
      post :retry
      post :requeue
    end
  end
  post "enqueue", to: "enqueue#create"
  get "up" => "rails/health#show", as: :rails_health_check
end
