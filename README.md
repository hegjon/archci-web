# archci-web

The web front end of an [archci](https://github.com/hegjon/archci) build
farm: the farm as `archci top` shows it, every job as a tree per package,
each job's story and log, and the operator's queue commands, on a host of
its own that reads the master over ssh.

It is a Rails application without a database. The master's snapshot is
its only state, fetched as the `web` key (`archci authorize --web` on the
master lets a key run `snapshot`, `log ID`, `retry`, `requeue` and
`enqueue`, nothing else) and kept for a few seconds; pages refresh
themselves every five seconds by a Turbo morph, so the filter box and the
scroll position stay put. The look is a terminal in
[Tokyo Night](https://github.com/enkia/tokyo-night-vscode-theme).

## Pages

- `/` the farm: queue and outstanding counts, built and released per
  arch, the sourcer's numbers, the hosts with load, disk and memory, the
  running builds with phase and stats, the newest failures
- `/jobs` every job the master holds, pending to failed, as a tree: one
  row per package, its src, any, x86_64, aarch64 ... jobs beneath it,
  filtered by words that must all appear in a job's state, package,
  version, arch, worker or origin (`failed aarch64 python`); `running`,
  `failed` and `sources` in the header are that filter
- `/jobs/<id>` one job: its story, the source package and network it had,
  its stats while it runs, and its log opened at the first error (a
  running job's is what its journal has streamed so far); retry and
  requeue buttons for the operator

The queue commands ask for the operator's password (`ARCHCI_WEB_PASSWORD`,
HTTP basic auth); without one configured they are off. The master logs
each as the web key's.

## Running it

```
git clone https://github.com/hegjon/archci-web /opt/archci-web
cd /opt/archci-web && bundle install --deployment
ssh-keygen -t ed25519 -N '' -f /etc/archci-web/web_key      # then, on the master:
archci authorize --web '<the .pub line>'
install -m 600 deploy/env.example /etc/archci-web/env       # fill in SECRET_KEY_BASE, the password
bin/rails assets:precompile
install -m 644 deploy/archci-web.service /etc/systemd/system/
systemctl enable --now archci-web
```

puma listens on 127.0.0.1:3000; `deploy/Caddyfile` puts caddy with TLS in
front. `master` must resolve to the master's address (`/etc/hosts`), as
for a worker. In development, `ARCHCI_MASTER=archci@<host>
ARCHCI_SSH_KEY=~/.ssh/archci_web_key bin/rails server` talks to a real
master; `bin/rails test` runs against a recorded snapshot
(`test/fixtures/files`), so the tests need no master.

## Layout

```
app/models/master.rb     the master over ssh: Master.run("snapshot"), .run("log", id), ...
app/models/farm.rb       the snapshot: counts, hosts, jobs, the tree per package, filtering
app/models/job.rb        one job: fields, story, its log from the master
app/controllers/         farm (the front page), jobs (tree, one job, retry, requeue), enqueue
app/views/               the pages; layouts/application.html.erb is the frame (header, footer)
app/javascript/controllers/refresh_controller.js   the timed Turbo morph
app/assets/stylesheets/application.css             Tokyo Night
deploy/                  the systemd unit, the environment file, a Caddyfile
test/                    models and pages against the recorded snapshot
```

MIT.
