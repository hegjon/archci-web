# frozen_string_literal: true

# One job of the master's queue, as the snapshot lists it: the job file's
# fields plus its state (the queue it is in), origin and story.
class Job
  STATES = %w[pending running done failed].freeze
  ARCH_ORDER = %w[src any x86_64 x86_64_v4 aarch64 riscv64].freeze
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
     created claimed finished started log rss peak build load exported retried_as pkgbuilds pkgbuilds_dir].each do |k|
    define_method(k) { @data[k] }
  end

  # the PKGBUILD at the job's commit on the repository's web site, for
  # GitHub and GitLab URLs (the master names the repository, ARCHCI_PKGBUILDS_URL);
  # nil for any other host, where the page's own PKGBUILD panel still shows it
  def pkgbuild_url
    return nil unless commit.present? && pkgbuilds.present?

    base = pkgbuilds.delete_suffix(".git")
    path = "#{pkgbuilds_dir.presence || 'pkgbuilds'}/#{pkgbase}/PKGBUILD"
    case base
    when %r{\Ahttps://github\.com/} then "#{base}/blob/#{commit}/#{path}"
    when %r{\Ahttps://gitlab\.com/} then "#{base}/-/blob/#{commit}/#{path}"
    end
  end

  def attempt = @data["attempt"].to_i
  def final? = @data["final"] == "1"
  def mtime = Time.iso8601(@data["mtime"])
  def running? = state == "running"
  def pending? = state == "pending"
  def failed? = state == "failed"
  def finished? = %w[done failed].include?(state)
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

  # the exported log's URL on R2 (ARCHCI_RELEASE_URL, the release the master
  # publishes to): <url>/<repo>/log/<pkgbase>/<version>/<arch>/<file>, the
  # file the job record names (exported=, by archci-publish once the journal
  # had the whole log). nil before the export, for a job the journal held
  # nothing of ("none"), or without the URL. The browser opens an
  # EventSource on it: the same stream `archci web sse` gives live, stored
  # once, gzip, decoded by the browser itself (Content-Encoding).
  def log_url
    base = ENV["ARCHCI_RELEASE_URL"].presence or return nil
    return nil unless exported.present? && exported != "none"

    "#{base.chomp('/')}/#{repo}/log/#{pkgbase}/#{version}/#{arch}/#{exported}"
  end
end
