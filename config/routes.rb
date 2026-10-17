Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  scope module: :web do
    root "home#show"
    resource :session, only: %i[new create destroy]
    resources :users, only: %i[index show new create edit update]
    resources :roles, :branches, :departments, :legal_entities, :rejection_reasons,
      only: %i[index new create edit update]
    resources :candidates, only: %i[index show new create edit update] do
      resources :resumes, only: %i[index show create], controller: :candidate_resumes
    end
    resources :vacancy_templates, only: %i[index show new create edit update] do
      post :approve, on: :member
    end
    resources :job_requisitions, only: %i[index show new create edit update] do
      member do
        post :pause
        post :resume
        post :cancel
      end
    end
    resources :recruitment_campaigns, only: %i[index show] do
      post :launch, on: :member
    end
    resources :candidate_applications, only: :create do
      member do
        post :advance
        post :finish
      end
    end
  end

  namespace :api do
    namespace :v1 do
      resource :session, only: %i[create destroy]
      resource :me, only: :show, controller: :me
      resources :branches, :departments, :legal_entities, :users, only: %i[index show create update]
      resources :roles, only: %i[index create update]
      resources :audit_events, only: :index
      resources :vacancy_templates, only: %i[index show create update] do
        member do
          post :approve
          get :versions
        end
      end
      resources :job_requisitions, only: %i[index show create update] do
        member do
          post :pause
          post :resume
          post :cancel
          get :versions
        end
      end
      resources :recruitment_campaigns, only: %i[index show] do
        post :launch, on: :member
      end
      resources :candidates, only: %i[index show create update] do
        resources :resumes, only: %i[index show create], controller: :candidate_resumes
      end
      resources :candidate_applications, only: %i[index show create] do
        post :advance, on: :member
        post :finish, on: :member
      end
      resources :candidate_imports, only: %i[index show create]
      resources :candidate_duplicates, only: :index do
        post :resolve, on: :member
      end
      resources :rejection_reasons, only: %i[index create update]
    end
  end
end
