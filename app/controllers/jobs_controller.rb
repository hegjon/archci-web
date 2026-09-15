# frozen_string_literal: true

# Every job as a tree per package (index, filtered by words), one job with
# its story and log (show), and the operator's commands on it.
class JobsController < ApplicationController
  before_action :require_operator, only: %i[retry requeue]
  before_action :find_job, only: %i[show log retry requeue]

  def index
    @words = params[:q].to_s.split
    @packages = @farm.packages(@words)
    @total = @packages.size
    @packages = @packages.first(Farm::PAGE)
  end

  def show
    @repo = @job.repo
    @generated = @job.generated
    # The log is not rendered here: the browser builds the log window from
    # the journal entries the log action below returns, and, for a running
    # job, keeps asking it for the entries it has not seen yet.
  end

  # the job's log as journal entries (JSON), for the log Stimulus controller:
  # the whole log, or the entries that follow ?after=<cursor> for a running
  # job, and the cursor to resume from next time. A read: no operator
  # password needed.
  def log
    render json: @job.log_entries(params[:after].presence).to_h
  rescue Farm::Unavailable => e
    render json: { error: e.message }, status: :bad_gateway
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
    return if @job

    if action_name == "log"
      render json: { error: "no job #{id}" }, status: :not_found
    else
      render "shared/not_found", status: :not_found
    end
  end
end
