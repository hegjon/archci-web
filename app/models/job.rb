# frozen_string_literal: true

# One job of the master's queue, as the snapshot lists it: the job file's
# fields plus its state (the queue it is in), origin and story.
class Job
  STATES = %w[pending running done failed].freeze
  ARCH_ORDER = %w[src any x86_64 aarch64 riscv64].freeze
  FIELDS = %w[state pkgbase version arch worker origin].freeze   # what a filter word is matched against
  MAX_ATTEMPTS = 3

  attr_reader :data

  def initialize(data)
    @data = data
  end

  # one job by id, straight from the master (archci web job ID); nil if gone
  def self.find(id)
    new(JSON.parse(Master.run("job", id)))
  rescue Master::Error
    nil
  rescue JSON::ParserError => e
    raise Farm::Unavailable, e.message
  end

  %w[id state arch pkgbase version worker origin story sources network phase repo commit profile
     created claimed finished started stopped online_at build_at log rss peak build load].each do |k|
    define_method(k) { @data[k] }
  end

  def attempt = @data["attempt"].to_i
  def final? = @data["final"] == "1"
  def mtime = Time.iso8601(@data["mtime"])
  def running? = state == "running"
  def pending? = state == "pending"
  def failed? = state == "failed"
  def at = finished || claimed || created
  def arch_rank = ARCH_ORDER.index(arch) || 99
  def retryable? = failed?
  def requeueable? = running? || failed?

  def matches?(words)
    words.all? { |w| FIELDS.any? { |f| @data[f].to_s.downcase.include?(w.downcase) } }
  end

  def to_param = id.tr(",", "/")   # prettier URL: prio-ts-repo/pkgbase/version/arch
  def repo = @data["repo"]
  def generated = @data["generated"] && Time.iso8601(@data["generated"])
  def sources_job = @data["sources_job"]

  # the job's log from the master as journal entries (archci web entries):
  # {entries: [{__CURSOR, __REALTIME_TIMESTAMP, MESSAGE, phase?}], error_at,
  # state, cursor}, what the browser builds the log window from. With a
  # cursor (after), only the entries that follow it, so a poll of a running
  # job fetches just the new ones; without, the whole log so far.
  def log_entries(after = nil)
    Log.new(JSON.parse(Master.run("entries", *[ id, after ].compact)))
  rescue Master::Error, JSON::ParserError => e
    raise Farm::Unavailable, e.message
  end

  Log = Struct.new(:data) do
    def entries = data["entries"]
    def error_at = data["error_at"]
    def state = data["state"]
    def cursor = data["cursor"]
    def to_h = data
  end
end
