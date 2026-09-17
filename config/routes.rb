Rails.application.routes.draw do
  root "farm#show"
  get "jobs", to: "jobs#index", as: :jobs
  # a job id is prio-ts-repo,pkgbase,version,arch; the URL renders the commas
  # as slashes (prettier), so the id spans path segments and needs a glob
  # a job's log as server-sent events (before the catch-all show, whose glob
  # would otherwise swallow the /sse); a running job's streams until it ends
  get "jobs/*id/sse", to: "jobs#sse", as: :sse_job, format: false
  # the PKGBUILD the job was built from, as a turbo frame the job page loads when its panel is opened
  get "jobs/*id/pkgbuild", to: "jobs#pkgbuild", as: :pkgbuild_job, format: false
  get "jobs/*id", to: "jobs#show", as: :job, format: false
  post "jobs/*id/retry", to: "jobs#retry", as: :retry_job, format: false
  post "jobs/*id/requeue", to: "jobs#requeue", as: :requeue_job, format: false
  post "enqueue", to: "enqueue#create"
  get "up" => "rails/health#show", as: :rails_health_check
end
