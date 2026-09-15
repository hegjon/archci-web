ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# The master, faked: the fixtures are a real snapshot and two logs taken
# from the test instance with the web key. Commands are recorded.
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
      if j["sources"] && j["arch"] != "src"
        src = snap["jobs"].find { |x| x["arch"] == "src" && x["pkgbase"] == j["pkgbase"] && x["version"] == j["version"] }
        extra["sources_job"] = src["id"] if src
      end
      JSON.generate(j.merge(extra))
    in [ "log", id, * ] if id.include?("grub") then Rails.root.join("test/fixtures/files/log.json").read
    in [ "log", id, * ] if id.include?("eza") then Rails.root.join("test/fixtures/files/running-log.json").read
    in [ "log", id, * ] then raise Master::Error, "archci-web: no job #{id}"
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
