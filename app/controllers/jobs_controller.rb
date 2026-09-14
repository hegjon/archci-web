# frozen_string_literal: true

# Every job as a tree per package (index, filtered by words), one job with
# its story and log (show), and the operator's commands on it.
class JobsController < ApplicationController
  before_action :require_operator, only: %i[retry requeue]
  before_action :find_job, only: %i[show retry requeue]

  def index
    @words = params[:q].to_s.split
    @packages = @farm.packages(@words)
    @total = @packages.size
    @packages = @packages.first(Farm::PAGE)
  end

  def show
    @repo = @job.repo
    @generated = @job.generated
    # A running job's log is the tail of what its journal has streamed to the
    # master so far; the page refetches it every few seconds (the refresh
    # controller). journalctl -f cannot follow a journald-remote journal, so
    # this polls the tail rather than streaming.
    @log = @job.log_lines
  end

  def retry
    master_command("retry", @job.id)
  end

  def requeue
    master_command("requeue", @job.id)
  end

  private

  # show and stream fetch just the one job (no snapshot); retry and requeue
  # already loaded the farm via the before_action
  def find_job
    id = params[:id].to_s.tr("/", ",")   # the URL slashes are the real id's commas
    @job = @farm ? @farm.job(id) : Job.find(id)
    render("shared/not_found", status: :not_found) unless @job
  end
end
