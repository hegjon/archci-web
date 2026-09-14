require "test_helper"

class PagesTest < ActionDispatch::IntegrationTest
  test "the farm page shows the queue, hosts, running and failed jobs" do
    get root_path
    assert_response :success
    assert_select "header .brand .repo", "hegjon-test"
    assert_select ".counter", minimum: 4
    assert_select "table tbody tr td", text: "worker3"
    assert_select "table tbody tr td a", text: "eza 0.23.5-2.1"
    assert_select "footer", /master archci 0\.4\.24-1/
  end

  test "the jobs page is a tree per package, filtered by words" do
    get jobs_path
    assert_response :success
    assert_select "tr.pkg", Farm::PAGE
    assert_select "input#q[value='']"
    get jobs_path(q: "failed grub")
    assert_select "tr.pkg", 1
    assert_select "tr.job .badge-failed"
    assert_select "tr.job .badge-done", 0
  end

  test "a job page shows its story, facts and log with the first error" do
    id = "5-1788893881-hegjon-test,grub,2:2.14-1,x86_64"
    get job_path(id)
    assert_response :success
    assert_select "section.job h2", /grub 2:2\.14-1/
    assert_select "dl.facts dd", text: id
    assert_select "pre.log .line.err", 1
    assert_select "pre.log .line", minimum: 100
    assert_select "form[action=?]", retry_job_path(id), 0   # no operator password: no buttons
    assert_select "body[data-refresh-interval-value='0']"
  end

  test "the queue buttons show only when an operator password is set" do
    id = "5-1788893881-hegjon-test,grub,2:2.14-1,x86_64"
    get job_path(id)
    assert_select ".actions", 0
    ENV["ARCHCI_WEB_PASSWORD"] = "s3cret"
    get job_path(id)
    assert_select "form[action=?]", retry_job_path(id)
  ensure
    ENV["ARCHCI_WEB_PASSWORD"] = nil
  end

  test "a running job's page refreshes every few seconds and shows the log tail" do
    id = "5-1789349629-hegjon-test,eza,0.23.5-2.1,riscv64"
    get job_path(id)
    assert_response :success
    # its source package links to the src job that produced it
    assert_select "dl.facts dd a[href=?]", job_path("1-1789344688-hegjon-test,eza,0.23.5-2.1,src"), text: /\.src\.tar\.gz/
    assert_select "body[data-refresh-interval-value='5000'][data-controller='refresh']"
    assert_includes FakeMaster.calls, [ "log", id ]   # the tail is polled, not streamed
  end

  test "a finished job's page does not refresh" do
    get job_path("5-1788893881-hegjon-test,grub,2:2.14-1,x86_64")
    assert_select "body[data-refresh-interval-value='0'][data-controller='refresh']"
  end

  test "an unknown job is not found" do
    get job_path("9-1-x,nope,1-1,x86_64")
    assert_response :not_found
  end

  test "an unreachable master gives a page that says so" do
    Master.runner = ->(*) { raise Master::Error, "Connection refused" }
    get root_path
    assert_response :service_unavailable
    assert_select "h2", /unreachable/
    assert_select ".dot.offline"
  ensure
    Master.runner = FakeMaster::RUNNER
  end
end
