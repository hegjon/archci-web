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
    @log = @job.log_lines
  end

  def retry
    master_command("retry", @job.id)
  end

  def requeue
    master_command("requeue", @job.id)
  end

  private

  def find_job
    @job = @farm.job(params[:id]) or render("shared/not_found", status: :not_found)
  end
end
