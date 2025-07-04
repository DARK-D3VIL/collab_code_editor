Rails.application.routes.draw do
  devise_for :users, controllers: {
    registrations: "users/registrations",
    sessions: "users/sessions",
    omniauth_callbacks: "users/omniauth_callbacks"
  }
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  devise_scope :user do
    get "users/email_verification", to: "users/registrations#email_verification", as: :email_verification
    post "users/verify_email", to: "users/registrations#verify_email", as: :verify_email
    post "users/resend_verification", to: "users/registrations#resend_verification", as: :resend_verification
  end

  # Mount Sidekiq Web UI
  if Rails.env.development?
    mount Sidekiq::Web => "/sidekiq"
  else
    # In production, protect the Sidekiq UI
    authenticate :user, ->(user) { user.admin? rescue false } do
      mount Sidekiq::Web => "/admin/sidekiq"
    end
  end
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Defines the root path route ("/")
  # root "posts#index"
  root to: "projects#index"

  namespace :api do
    resources :ai, only: [] do
      collection do
        post :completions
      end
    end
  end

  resources :conflicts, only: [ :index, :show, :destroy ] do
    member do
      post :resolve
      delete :ignore
    end

    collection do
      get :file_conflicts
      post :bulk_resolve
    end
  end

  resources :user_join_requests, only: [ :index, :destroy ], path: "my-requests"

  get "/settings", to: "user_settings#index", as: "user_settings"
  patch "/settings/profile", to: "user_settings#update_profile", as: "update_profile"
  patch "/settings/password", to: "user_settings#update_password", as: "update_password"
  get "/settings/export", to: "user_settings#export_data", as: "export_user_data"

  # Account deletion with OTP verification
  post "/settings/request_deletion_otp", to: "user_settings#request_deletion_otp", as: "request_deletion_otp"
  delete "/settings/account", to: "user_settings#destroy_account", as: "delete_account"

  # Project management from settings
  delete "/projects/:id/leave", to: "user_settings#leave_project", as: "leave_project"
  delete "/projects/:id/delete", to: "user_settings#delete_project", as: "delete_project"

  get "/github_repos", to: "github#repos"
  post "/github_clone", to: "github#clone", as: :github_clone
  delete "/github/projects/:project_id/unlink", to: "github#unlink_repository", as: "github_project_unlink"
  post "github/clone_public", to: "github#clone_public", as: "github_clone_public"

  resources :projects do
    collection do
      post "join"
      post "upload"
    end
    scope path: "github", as: "github" do
      get "sync", to: "github#sync"
      post "link", to: "github#link_repository", as: "link_repository"
      post "push", to: "github#push_to_github", as: "push"
    end
    resources :project_members, only: [ :index ] do
      member do
        patch :deactivate
        patch :activate
        patch :change_role
      end
      collection do
        patch :approve_request
        patch :reject_request
      end
    end

    resources :project_files, path: "files", param: :id, constraints: { id: /[^\/]+/ }  do
      collection do
        post :create_folder
        delete :destroy_file
        delete :destroy_folder
        post :commit_all
      end
      member do
        get :edit
        post :save
        post :commit
      end
    end

    # Project version control Routes
    get    "git",                         to: "project_git#show",            as: :git
    get    "git/branches",                to: "project_git#branches",        as: :git_branches
    post   "git/branches",                to: "project_git#create_branch"
    post   "git/branches/:id/switch",     to: "project_git#switch",         as: :git_switch_branch
    get    "git/branches/:id/commits",    to: "project_git#commits",        as: :git_branch_commits
    get    "git/branches/:id/commit/:sha", to: "project_git#commit_diff",    as: :git_branch_commit
    post   "git/branches/:id/rollback",   to: "project_git#rollback",       as: :git_branch_rollback
    post   "git/branches/:id/merge",      to: "project_git#merge",          as: :git_merge_branch
    delete "git/branches/:id",            to: "project_git#destroy_branch", as: :git_branch
    post "git/branches/:id/revert", to: "project_git#revert", as: :git_branch_revert

    # Project Settings Routes
    get "settings", to: "project_settings#show", as: :settings
    patch "settings", to: "project_settings#update"
    delete "settings", to: "project_settings#destroy"
    get "settings/ai_training_status", to: "project_settings#ai_training_status", as: :ai_training_status
  end
  match "/404", to: "errors#not_found", via: :all
  match "/422", to: "errors#unprocessable_entity", via: :all
  match "/500", to: "errors#internal_server_error", via: :all

  # Catch-all route fallback
  match "*path", to: "errors#not_found", via: :all

  mount ActionCable.server => "/cable"
end
