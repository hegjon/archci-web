# frozen_string_literal: true

# The farm as the master's snapshot describes it (`archci web snapshot`):
# the queue, the hosts, the running and failed jobs, the signer, and every
# job the master holds. Fetched over ssh and kept for a few seconds, so a
# page and its refreshes share one call.
class Farm
  TTL = 3.seconds
  PAGE = 150   # packages shown at once in the tree

  class Unavailable < StandardError; end

  def self.current
    Rails.cache.fetch("farm/snapshot", expires_in: TTL) { Master.run("snapshot") }
                .then { |json| new(JSON.parse(json)) }
  rescue Master::Error, JSON::ParserError => e
    raise Unavailable, e.message
  end

  attr_reader :data

  def initialize(data)
    @data = data
  end

  %w[repo arches queue outstanding sources tracked built signer hosts running failed].each do |k|
    define_method(k) { @data[k] }
  end

  def generated = Time.iso8601(@data["generated"])
  def done_last_hour = @data["done_last_hour"]

  def jobs
    @jobs ||= @data["jobs"].map { |j| Job.new(j) }
  end

  def job(id)
    jobs.find { |j| j.id == id }
  end

  # the tree: packages by their newest job, each with its jobs in arch order,
  # for the jobs whose fields hold every word of the filter
  def packages(words = [])
    jobs.select { |j| j.matches?(words) }
        .group_by(&:pkgbase)
        .sort_by { |_, js| -js.map(&:mtime).max.to_f }
        .map { |name, js| [ name, js.sort_by { |j| [ j.arch_rank, j.arch, -j.mtime.to_f ] } ] }
  end

  def master_version
    hosts.find { |h| h["host"] == "master" }&.dig("archci") || hosts.filter_map { |h| h["archci"] }.first
  end

  # built and released, per arch: what archci top's second and third lines say
  def built_line
    sets = arches.map { |a| "#{repo}-#{a}" } + [ "#{repo}-any" ]
    sets.map { |s| [ s.delete_prefix("#{repo}-"), built[s], tracked[s] ] }
  end
end
