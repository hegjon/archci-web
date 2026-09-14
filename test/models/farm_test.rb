require "test_helper"

class FarmTest < ActiveSupport::TestCase
  test "the snapshot is fetched once within its ttl" do
    Farm.current
    Farm.current
    assert_equal [ [ "snapshot" ] ], FakeMaster.calls
  end

  test "the farm reads the snapshot's counters" do
    farm = Farm.current
    assert_equal "hegjon-test", farm.repo
    assert_equal %w[x86_64 aarch64 riscv64], farm.arches
    assert_equal 181, farm.queue["pending"]
    assert_equal 2874, farm.jobs.size
    assert_equal "0.4.24-1", farm.master_version
    assert_equal [ "x86_64", 1389, 2015 ], farm.built_line.first
  end

  test "packages group the jobs by name, newest first, in arch order" do
    farm = Farm.current
    name, jobs = farm.packages.first
    assert_equal "eza", name
    assert_equal %w[src x86_64 aarch64 riscv64], jobs.map(&:arch).uniq
    assert farm.packages(%w[failed grub]).all? { |_, js| js.all? { |j| j.failed? && j.pkgbase.include?("grub") } }
    assert_empty farm.packages(%w[nosuchpackage])
  end

  test "a job tells its story and matches filter words" do
    job = Farm.current.job("5-1788893881-hegjon-test,grub,2:2.14-1,x86_64")
    assert job.failed?
    assert job.final?
    assert_match(/\Afailed .* on .*, attempt 3 of 3: gave up/, job.story)
    assert job.matches?(%w[FAILED x86_64 grub])
    assert_not job.matches?(%w[grub aarch64])
  end

  test "a job's log comes from the master with its first error" do
    log = Farm.current.job("5-1788893881-hegjon-test,grub,2:2.14-1,x86_64").log_lines
    assert_operator log.lines.size, :>, 100
    assert_kind_of Integer, log.error_at
    assert_match(/error|ERROR/, log.lines[log.error_at])
  end

  test "an unreachable master is Farm::Unavailable" do
    Master.runner = ->(*) { raise Master::Error, "ssh: connect to host master port 22: Connection refused" }
    assert_raises(Farm::Unavailable) { Farm.current }
  ensure
    Master.runner = FakeMaster::RUNNER
  end
end
