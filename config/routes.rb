Rails.application.routes.draw do
  root "farm#show"
  get "jobs", to: "jobs#index", as: :jobs
  # a job id is prio-ts-repo,pkgbase,version,arch; the URL renders the commas
  # as slashes (prettier), so the id spans path segments and needs a glob
  # a running job's log is polled here for the lines after ?after=<cursor>
  # (before the catch-all show, whose glob would otherwise swallow the /log)
  get "jobs/*id/log", to: "jobs#log", as: :log_job, format: false
  get "jobs/*id", to: "jobs#show", as: :job, format: false
  post "jobs/*id/retry", to: "jobs#retry", as: :retry_job, format: false
  post "jobs/*id/requeue", to: "jobs#requeue", as: :requeue_job, format: false
  post "enqueue", to: "enqueue#create"
  get "up" => "rails/health#show", as: :rails_health_check
end
