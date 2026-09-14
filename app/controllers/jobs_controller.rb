# frozen_string_literal: true

# Every job as a tree per package (index, filtered by words), one job with
# its story and log (show), and the operator's commands on it.
class JobsController < ApplicationController
  include ActionController::Live

  before_action :require_operator, only: %i[retry requeue]
  before_action :find_job, only: %i[show stream retry requeue]

  def index
    @words = params[:q].to_s.split
    @packages = @farm.packages(@words)
    @total = @packages.size
    @packages = @packages.first(Farm::PAGE)
  end

  def show
    @log = @job.log_lines
  end

  # A running job's journal, live, as server-sent events: "reset" once the
  # stream is open (the page drops what it rendered; the master's follow
  # starts with the last lines), "line" per line, "end" when the job is no
  # longer running. The connection holds a puma thread and an ssh channel
  # for as long as the page is open.
  def stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    sse = SSE.new(response.stream)
    unless @job.running?
      sse.write({ state: @job.state }, event: "end")
      return
    end
    sse.write({}, event: "reset")
    Master.stream("follow", @job.id) { |line| sse.write({ line: line }, event: "line") }
    sse.write({ state: "finished" }, event: "end")
  rescue Master::Error => e
    sse.write({ error: e.message }, event: "end")
  rescue ActionController::Live::ClientDisconnected, IOError
    nil
  ensure
    sse&.close
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
