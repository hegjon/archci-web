# frozen_string_literal: true

# Every job as a tree per package (index, filtered by words), one job with
# its story and log (show), and the operator's commands on it.
class JobsController < ApplicationController
  include ActionController::Live

  before_action :require_operator, only: %i[retry requeue]
  before_action :find_job, only: %i[show sse pkgbuild retry requeue]

  def index
    @words = params[:q].to_s.split
    @packages = @farm.packages(@words)
    @total = @packages.size
    @packages = @packages.first(Farm::PAGE)
  end

  def show
    @repo = @job.repo
    @generated = @job.generated
    # The log is not rendered here: the browser opens an EventSource on it,
    # the exported file on R2 for a finished job (Job#log_url), the sse
    # action below for a running one or when R2 has no file yet.
  end

  # the job's log as server-sent events, what the master's `archci web sse`
  # writes (the job event, one event per journal entry with its cursor as
  # the id, the end event once finished), streamed to a browser's
  # EventSource. A finished job's whole log at once; a running job's what
  # there is, then, every POLL seconds, what followed the last cursor, until
  # the end event. ?after=<cursor> or the Last-Event-ID header a reconnecting
  # EventSource sends resume from there. A read: no operator password needed.
  POLL = ENV.fetch("ARCHCI_SSE_POLL_SECONDS", "2").to_f
  LIMIT = 45.minutes   # a stream ends here at the latest; the browser reconnects from its last id
  def sse
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    cursor = params[:after].presence || request.headers["Last-Event-ID"].presence
    deadline = Time.now + LIMIT
    loop do
      chunk = Master.run("sse", *[ @job.id, cursor ].compact)
      response.stream.write(chunk) unless chunk.empty?
      cursor = chunk.scan(/^id: (\S+)$/).last&.first || cursor
      break if chunk.include?("\nevent: end\n") || !@job.running? || Time.now > deadline

      sleep POLL
      @job = Job.find(@job.id) || break
    end
  rescue Master::Error => e
    response.stream.write("event: error\ndata: #{JSON.generate(message: e.message)}\n\n")
  rescue ActionController::Live::ClientDisconnected, IOError
    # the reader went away
  ensure
    response.stream.close
  end

  # the PKGBUILD the job was built from, at its commit, as the master's
  # `archci web pkgbuild` shows it: a turbo frame the job page's PKGBUILD
  # panel loads when opened (lazy), so a page view costs no extra call
  def pkgbuild
    @pkgbuild = Master.run("pkgbuild", @job.id)
    render layout: false
  rescue Master::Error => e
    @error = e.message
    render layout: false
  end

  # a retry is a new job in the failed one's place: the master prints its
  # id, and that is the page to go to (the old id has no job any more)
  def retry
    out = Master.run("retry", @job.id)
    Rails.cache.delete("farm/snapshot")
    new_id = out.lines.map(&:strip).find { |l| l.match?(/\A\d+-\d+-\S+,\S+,\S+,\S+\z/) }
    if new_id
      redirect_to job_path(new_id.tr(",", "/")), notice: "retried as a new job, #{new_id}"
    else
      redirect_back_or_to root_path, notice: out.strip.presence || "retry done"
    end
  rescue Master::Error => e
    redirect_back_or_to root_path, alert: e.message
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

    if %w[sse pkgbuild].include?(action_name)
      render plain: "no job #{id}", status: :not_found
    else
      render "shared/not_found", status: :not_found
    end
  end
end
