# archci-web

The web front end of an [archci](https://github.com/hegjon/archci) build
farm: the farm as `archci top` shows it, every job as a tree per package,
each job's story and log, and the operator's queue commands, on a host of
its own that reads the master over ssh.

It is a Rails application without a database. The master's snapshot is
its only state, fetched as the `web` key (`archci authorize --web` on the
master lets a key run `snapshot`, `job ID`, `log ID`, `entries ID`,
`retry`, `requeue` and `enqueue`, nothing else) and kept for a few
seconds; pages refresh
themselves every five seconds by a Turbo morph, so the filter box and the
scroll position stay put. The look is a terminal in
[Tokyo Night](https://github.com/enkia/tokyo-night-vscode-theme).

## Pages

- `/` the farm: queue and outstanding counts (with how many pending jobs
  are held: outside the master's package filter, or waiting for a source
  package), built and released per arch, the sourcer's numbers, the hosts
  with load, disk and memory, the running builds with phase and stats, the
  newest failures
- `/jobs` every job the master holds, pending to failed, as a tree: one
  row per package, its src, any, x86_64, aarch64 ... jobs beneath it,
  filtered by words that must all appear in a job's state, package,
  version, arch, worker or origin (`failed aarch64 python`); `running`,
  `failed` and `sources` in the header are that filter
- `/jobs/<id>/pkgbuild` the PKGBUILD the job was built from, at its
  commit, as a turbo frame; the job page's PKGBUILD panel loads it when
  opened (the master's `archci web pkgbuild`)
- `/jobs/<id>` one job: its story, the source package and network it had,
  its stats while it runs, and its log opened at the first error; retry
  and requeue buttons for the operator. The log window is built in the
  browser from the log's stream of server-sent events, the framing the
  master's `archci web sse` writes: the job, one event per journal line
  (its time as the line number's tooltip, its journal cursor as the event
  id), the end. A finished job's log is the file archci-publish exported
  to the release (`ARCHCI_RELEASE_URL`,
  `<repo>/log/<pkgbase>/<version>/<arch>/<file>.sse.gz`), which the
  browser's `EventSource` reads straight from R2 and decodes itself
  (`Content-Encoding: gzip`; the bucket needs a CORS rule for this site's
  origin); when that fails (not exported yet, no CORS) `/jobs/<id>/sse`
  serves the same stream from the master. A running
  job's log streams from `/jobs/<id>/sse` as it grows, the master polled
  by cursor; a dropped connection resumes from `Last-Event-ID`

The queue commands ask for the operator's password (`ARCHCI_WEB_PASSWORD`,
HTTP basic auth); without one configured they are off. The master logs
each as the web key's.

## Running it

On an Arch host, with the system Ruby (the app pins no version):

```
pacman -S ruby ruby-bundler base-devel caddy git
useradd -r -m -d /opt/archci-web archci-web
git clone https://github.com/hegjon/archci-web /opt/archci-web      # as archci-web
cd /opt/archci-web
bundle config set --local deployment true
bundle config set --local without 'development test'
bundle install

install -d -m 750 -o root -g archci-web /etc/archci-web
ssh-keygen -t ed25519 -N '' -f /etc/archci-web/web_key              # then, on the master:
archci authorize --web "$(cat /etc/archci-web/web_key.pub)"
install -m 640 -o root -g archci-web deploy/env.example /etc/archci-web/env
bin/rails secret                                                    # paste into SECRET_KEY_BASE=
$EDITOR /etc/archci-web/env                                         # the key, the master, the password

bin/rails assets:precompile
install -m 644 deploy/archci-web.service /etc/systemd/system/
systemctl enable --now archci-web
```

puma listens on 127.0.0.1:3000; put caddy in front (`deploy/Caddyfile`)
with a domain, and it fetches a TLS certificate (production forces SSL, as
Rails does by default; caddy terminates it). `master` must resolve to the
master's address (`/etc/hosts`), as for a worker.

To update a running deployment: `bin/deploy` (fetch master, install gems,
precompile, restart).

In development, `ARCHCI_MASTER=archci@<host> ARCHCI_SSH_KEY=~/.ssh/archci_web_key
bin/rails server` talks to a real master; `bin/rails test` runs against a
recorded snapshot and two recorded logs (`test/fixtures/files`), so the
tests need no master. `ARCHCI_SSE_POLL_SECONDS` (2) is how often a running
job's stream asks the master for more.

## Layout

```
app/models/master.rb     the master over ssh: Master.run("snapshot"), .run("entries", id), ...
app/models/farm.rb       the snapshot: counts, hosts, jobs, the tree per package, filtering
app/models/job.rb        one job: fields, story, its log as journal entries from the master
app/controllers/         farm (the front page), jobs (tree, one job, retry, requeue), enqueue
app/views/               the pages; layouts/application.html.erb is the frame (header, footer)
app/javascript/controllers/refresh_controller.js   the timed Turbo morph (re-polls a running job's log)
app/assets/stylesheets/application.css             Tokyo Night
deploy/                  the systemd unit, the environment file, a Caddyfile
bin/deploy               update a running deployment: fetch, bundle, precompile, restart
test/                    models and pages against the recorded snapshot
```

MIT.
