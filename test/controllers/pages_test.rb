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
    assert_select "dl.facts dd", text: "1m 43s"   # build time, from the log's start and finish lines
    assert_select "pre.log .line.phase-online", 1   # the online->offline slice markers are highlighted
    assert_select "pre.log .line.phase-offline", 1
    assert_select "form[action=?]", retry_job_path(id), 0   # no operator password: no buttons
    assert_select "body[data-refresh-interval-value='0']"
  end

  test "the queue buttons show only when an operator password is set" do
    id = "5-1788893881-hegjon-test,grub,2:2.14-1,x86_64"
    get job_path(id)
    assert_select ".actions", 0
    ENV["ARCHCI_WEB_PASSWORD"] = "s3cret"
    get job_path(id)
    assert_select "form[action=?]", retry_job_path(id.tr(",", "/"))
  ensure
    ENV["ARCHCI_WEB_PASSWORD"] = nil
  end

  test "a running job's page refreshes and wires the log controller to poll deltas" do
    id = "5-1789349629-hegjon-test,eza,0.23.5-2.1,riscv64"
    get job_path(id)
    assert_response :success
    # its source package links to the src job that produced it
    assert_select "dl.facts dd a[href=?]", job_path("1-1789344688-hegjon-test/eza/0.23.5-2.1/src"), text: /\.src\.tar\.gz/
    assert_select "body[data-refresh-interval-value='5000'][data-controller='refresh']"
    # the log is loaded and appended client-side, not rendered (or re-sent) here
    assert_select "section[data-controller='log'][data-log-url-value=?]", log_job_path(id.tr(",", "/"))
    assert_select "section[data-controller='log'][data-turbo-permanent]"
    assert_not_includes FakeMaster.calls.map(&:first), "log"   # show never fetches the log
    # build time so far (claimed -> now), refreshed by the page's morph
    assert_select "dl.facts dt", text: "build time"
    assert_select "dl.facts dd", /\A\d+(h \d+m|m \d+s|s)\z/
  end

  test "the log endpoint returns a running job's lines and a cursor to resume from" do
    id = "5-1789349629-hegjon-test,eza,0.23.5-2.1,riscv64"
    get log_job_path(id.tr(",", "/"))
    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal "running", body["state"]
    assert_operator body["lines"].size, :>, 0
    assert body["cursor"].present?
    assert_includes FakeMaster.calls, [ "log", id ]   # first poll: no cursor, the whole journal so far
  end

  test "the log endpoint passes the cursor through to the master" do
    id = "5-1789349629-hegjon-test,eza,0.23.5-2.1,riscv64"
    get log_job_path(id.tr(",", "/")), params: { after: "s=abc;i=100" }
    assert_response :success
    assert_includes FakeMaster.calls, [ "log", id, "s=abc;i=100" ]
  end

  test "the log endpoint is 404 JSON for an unknown job" do
    get log_job_path("9-1-x/nope/1-1/x86_64")
    assert_response :not_found
    assert_equal "application/json", @response.media_type
  end

  test "a finished job's page does not refresh" do
    get job_path("5-1788893881-hegjon-test,grub,2:2.14-1,x86_64")
    assert_select "body[data-refresh-interval-value='0'][data-controller='refresh']"
  end

  test "the job URL renders the id's commas as slashes and routes back" do
    slug = "5-1788893881-hegjon-test/grub/2:2.14-1/x86_64"
    job = Farm.current.job("5-1788893881-hegjon-test,grub,2:2.14-1,x86_64")
    assert_equal "/jobs/#{slug}", job_path(job)   # a Job renders its id with slashes
    get "/jobs/#{slug}"                            # and the slashed URL routes back
    assert_response :success
    assert_select "section.job h2", /grub 2:2\.14-1/
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
