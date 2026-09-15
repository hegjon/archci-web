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
- `/jobs/<id>` one job: its story, the source package and network it had,
  its stats while it runs, and its log opened at the first error; retry
  and requeue buttons for the operator. The log window is built in the
  browser from the job's journal entries (`archci web entries` on the
  master, proxied at `/jobs/<id>/log`): each line with the time it was
  written as the line number's tooltip and its journal cursor on the line,
  nothing read from files; a running job's is what has streamed so far,
  and the page fetches only the entries after the last cursor every few
  seconds until the job finishes

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
recorded snapshot (`test/fixtures/files`), so the tests need no master.

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
