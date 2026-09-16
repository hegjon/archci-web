ENV["RAILS_ENV"] ||= "test"
ENV["ARCHCI_SSE_POLL_SECONDS"] = "0"   # a running job's stream polls without waiting
ENV["ARCHCI_RELEASE_URL"] = "https://r2.example"
require_relative "../config/environment"
require "rails/test_help"

# The master, faked: the fixtures are a real snapshot from the test instance
# and two logs from it as the sse stream (framed with archci's own
# Archci.sse_entry from the journal entries recorded with the web key): the
# grub failure, whole, and the running eza build, first what there is, then,
# asked again with a cursor, one more line and the end. Commands are
# recorded.
module FakeMaster
  def self.calls = @calls ||= []

  def self.reset!
    @calls = []
    Rails.cache.clear
  end

  RUNNER = lambda do |*args|
    calls << args
    case args
    in [ "snapshot" ] then Rails.root.join("test/fixtures/files/snapshot.json").read
    in [ "job", id ]
      snap = JSON.parse(Rails.root.join("test/fixtures/files/snapshot.json").read)
      j = snap["jobs"].find { |x| x["id"] == id } or raise Master::Error, "archci-web: no job #{id}"
      extra = { "repo" => snap["repo"], "generated" => Time.now.utc.iso8601 }
      # as the master: a running job's "started" is its claim; a finished
      # one's times are the browser's, from the log
      extra["started"] = j["claimed"] if j["state"] == "running"
      if j["sources"] && j["arch"] != "src"
        src = snap["jobs"].find { |x| x["arch"] == "src" && x["pkgbase"] == j["pkgbase"] && x["version"] == j["version"] }
        extra["sources_job"] = src["id"] if src
      end
      JSON.generate(j.merge(extra))
    in [ "sse", id ] if id.include?("grub") then Rails.root.join("test/fixtures/files/sse-grub.txt").read
    in [ "sse", id ] if id.include?("eza") then Rails.root.join("test/fixtures/files/sse-eza.txt").read
    in [ "sse", id, cursor ] if id.include?("eza") then Rails.root.join("test/fixtures/files/sse-eza-end.txt").read
    in [ "sse", id, * ] then raise Master::Error, "archci-web: no job #{id}"
    in [ "retry" | "requeue", id ] then "archci-job: #{id} #{args.first}\n"
    in [ "enqueue", pkg, prio, arch ] then "archci-job: enqueued 0-1-x,#{pkg},1-1,#{arch}\n"
    end
  end
end
Master.runner = FakeMaster::RUNNER

module ActiveSupport
  class TestCase
    parallelize(workers: 1)
    setup { FakeMaster.reset! }
  end
end
