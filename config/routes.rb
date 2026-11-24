Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#show"
  get "alerts" => "alerts#index", as: :alerts
  get "report(/:day)" => "reports#show", as: :report
  get "billing" => "billing#show", as: :billing
end
