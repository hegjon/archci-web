require "test_helper"

class PagesTest < ActionDispatch::IntegrationTest
  test "the farm page shows the queue, hosts, running and failed jobs" do
    get root_path
    assert_response :success
    assert_select "header .brand .repo", "hegjon-test"
    assert_select ".counter", minimum: 4
    assert_select ".counter a", text: "pending 181"
    assert_select ".counter .muted", text: "(179 held)"   # pending jobs no claim takes: filtered out, or waiting for sources
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

  test "the farm page shows the signing pipeline: released per arch, what waits in the pool" do
    get root_path
    assert_select ".counter h2", text: "released"
    assert_select ".counter .pair", text: /x86_64 2427 pkg/
    assert_select ".counter .pair.muted", text: /unsigned 0 in the pool/
    assert_select ".counter .pair.warn", 0
  end

  test "a job page shows its story and facts, and wires the log window to the stream" do
    id = "5-1788893881-hegjon-test,grub,2:2.14-1,x86_64"
    get job_path(id)
    assert_response :success
    assert_select "section.job h2", /grub 2:2\.14-1/
    assert_select "dl.facts dd", text: id
    # a finished build's time (and its online/build split) is the log controller's, from the stream: a hidden slot until then
    assert_select "dl.facts dt", text: "build time"
    assert_select "dl.facts dd#build-time .spinner"   # until the controller has the stream
    assert_select "dl.facts dt", text: "peak memory"
    assert_select "dl.facts dd", text: /\A942M .* 239M build tree\z/   # the last heartbeat's numbers
    assert_select "dl.facts dd", text: /\A\d+m \d+s/, count: 0   # nothing computed server-side
    # the log window is built in the browser from the log's stream: the exported file on R2 for a finished job, the sse action behind it
    r2 = "https://r2.example/hegjon-test/log/grub/2:2.14-1/x86_64/grub-2:2.14-1-x86_64-1788967045-3c1e7b3f7ac54ac1b8b8bd3d8b1b5f7d.sse.zst"
    assert_select "section[data-controller='log'][data-log-url-value=?][data-log-r2-url-value=?][data-log-state-value='failed']", sse_job_path(id.tr(",", "/")), r2
    assert_select "dl.facts dd a[href=?]", r2, text: /\.sse\.zst\z/
    assert_select "pre.log[data-log-target='pre'][hidden]"
    assert_select "pre.log .line", 0
    assert_not_includes FakeMaster.calls.map(&:first), "sse"   # show never fetches the log
    assert_select "form[action=?]", retry_job_path(id), 0   # no operator password: no buttons
    assert_select "body[data-refresh-interval-value='0']"
  end

  test "a job page has a closed PKGBUILD panel the log controller fills, and links the commit to the repository" do
    id = "5-1788893881-hegjon-test,grub,2:2.14-1,x86_64"
    get job_path(id)
    assert_response :success
    assert_select "details.pkgbuild[data-turbo-permanent] summary", /PKGBUILD/
    assert_select "details.pkgbuild[open]", 0
    assert_select "details.pkgbuild pre.code#pkgbuild[hidden]"
    assert_select "details.pkgbuild p#pkgbuild-missing", /not in this log/
    assert_select "dl.facts dd a[href=?]", "https://github.com/hegjon/omarchy-pkgs/blob/#{Job.find(id).commit}/pkgbuilds/grub/PKGBUILD"
    assert_equal %w[job], FakeMaster.calls.map(&:first).uniq   # the page view asks the master for the job alone
  end

  test "the sse endpoint streams a finished job's whole log: the job event, one event per line with its cursor, the end" do
    id = "5-1788893881-hegjon-test,grub,2:2.14-1,x86_64"
    get sse_job_path(id.tr(",", "/"))
    assert_response :success
    assert_equal "text/event-stream", @response.media_type
    body = @response.body
    assert body.start_with?("event: job\ndata: {\"id\":\"#{id}\"")
    events = body.split("\n\n")
    assert_operator events.size, :>, 100
    assert(events[1..-2].all? { |e| e.match?(/\Adata: \{"time":"2026-.*\nid: s=/m) })   # each line's time in the data, its cursor as the id
    assert_equal %w[online offline], body.scan(/"phase":"(\w+)"/).flatten   # the online->offline slice markers
    assert body.end_with?("event: end\ndata: {\"state\":\"failed\",\"error_at\":257,\"finished\":\"2026-09-10T15:19:13Z\",\"rc\":4}\n\n")
    assert_equal [ [ "sse", id ] ], FakeMaster.calls.select { |c| c.first == "sse" }   # once: a finished job's stream ends with it
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
    # the log is streamed client-side from the sse action (no export yet: no R2 URL), not rendered here
    assert_select "section[data-controller='log'][data-log-url-value=?][data-log-r2-url-value=''][data-log-state-value='running']", sse_job_path(id.tr(",", "/"))
    assert_select "section[data-controller='log'][data-turbo-permanent]"
    assert_select "section[data-controller='log'] h2 .badge-live[data-log-target='live'][hidden]", text: "live"   # shown by the controller once the stream is open
    assert_select "dl.facts dd", text: /the journal so far, streamed/
    assert_not_includes FakeMaster.calls.map(&:first), "sse"   # show never fetches the log
    # build time so far (claimed -> now), refreshed by the page's morph
    assert_select "dl.facts dt", text: "build time"
    assert_select "dl.facts dd", /\A\d+(h \d+m|m \d+s|s)\z/
  end

  test "the sse endpoint streams a running job's log as it grows, asking the master from the last cursor, until the end" do
    id = "5-1789349629-hegjon-test,eza,0.23.5-2.1,riscv64"
    get sse_job_path(id.tr(",", "/"))
    assert_response :success
    assert_equal "text/event-stream", @response.media_type
    body = @response.body
    assert body.start_with?("event: job\n")
    assert_equal 5, body.scan(/^id: /).size   # 4 lines there at first, one more on the next poll
    assert body.end_with?("event: end\ndata: {\"state\":\"done\",\"error_at\":null,\"finished\":\"2026-09-14T01:50:00Z\",\"rc\":0}\n\n")
    calls = FakeMaster.calls.select { |c| c.first == "sse" }
    assert_equal [ "sse", id ], calls.first                                    # the whole log so far
    assert_equal [ "sse", id, body.scan(/^id: (\S+)$/)[3].first ], calls.last   # then from the last cursor seen
  end

  test "the sse endpoint resumes from ?after or the Last-Event-ID a reconnecting EventSource sends" do
    id = "5-1789349629-hegjon-test,eza,0.23.5-2.1,riscv64"
    get sse_job_path(id.tr(",", "/")), params: { after: "s=abc;i=100" }
    assert_response :success
    assert_equal [ "sse", id, "s=abc;i=100" ], FakeMaster.calls.find { |c| c.first == "sse" }
    FakeMaster.reset!
    get sse_job_path(id.tr(",", "/")), headers: { "Last-Event-ID" => "s=abc;i=200" }
    assert_equal [ "sse", id, "s=abc;i=200" ], FakeMaster.calls.find { |c| c.first == "sse" }
  end

  test "the sse endpoint is 404 for an unknown job" do
    get sse_job_path("9-1-x/nope/1-1/x86_64")
    assert_response :not_found
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
