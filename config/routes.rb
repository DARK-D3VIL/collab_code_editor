Rails.application.routes.draw do
  devise_for :users, controllers: {
    registrations: "users/registrations",
    omniauth_callbacks: "users/omniauth_callbacks"
  }
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Defines the root path route ("/")
  # root "posts#index"
  root to: "projects#index"

  resources :conflicts, only: [] do
    member do
      post :resolve
      post :ignore
    end

    collection do
      get :panel
    end
  end

  get "/github_repos", to: "github#repos"
  post "/github_clone", to: "github#clone", as: :github_clone
  delete "/github/projects/:project_id/unlink", to: "github#unlink_repository", as: "github_project_unlink"
  resources :projects do
    collection do
      post "join"
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
        # get :change_annotations
        get :edit
        post :save
        post :commit
      end
    end
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
  end
  match "/404", to: "errors#not_found", via: :all
  match "/422", to: "errors#unprocessable_entity", via: :all
  match "/500", to: "errors#internal_server_error", via: :all

  # Catch-all route fallback
  match "*path", to: "errors#not_found", via: :all

  mount ActionCable.server => "/cable"
end
