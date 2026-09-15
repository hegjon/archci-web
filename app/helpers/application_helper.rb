# frozen_string_literal: true

module ApplicationHelper
  # the queue commands (retry, requeue, enqueue) are on only when an operator
  # password is configured; otherwise their buttons are hidden
  def operator_commands?
    ENV["ARCHCI_WEB_PASSWORD"].present?
  end

  # "3m", "2h", "5d": how long ago, for tables
  def ago(time)
    return "-" if time.blank?

    time = Time.iso8601(time) if time.is_a?(String)
    seconds = (Time.now - time).to_i
    duration_short(seconds)
  end

  def duration_short(seconds)
    return "-" if seconds.nil?

    case seconds
    when ...60 then "#{seconds}s"
    when ...3600 then "#{seconds / 60}m"
    when ...86_400 then "#{seconds / 3600}h"
    else "#{seconds / 86_400}d"
    end
  end

  # hh:mm:ss since a time, for a running build
  def elapsed(since)
    return "-" if since.blank?

    s = (Time.now - Time.iso8601(since)).to_i
    format("%02d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
  end

  # how long the build took, from the stable start and stop the master reports
  # (Archci.build_span): "1h 12m", "4m 30s". A running build counts to now; a
  # build with no recorded start (an old log, a pending job) shows nothing.
  def build_time(job)
    return if job.started.blank?

    finish = if job.stopped.present? then Time.iso8601(job.stopped)
    elsif job.running? then Time.now
    end
    return unless finish

    duration_hms((finish - Time.iso8601(job.started)).to_i)
  end

  # a package build's online (dependency install, with the network) and offline
  # (the build itself) portions, from the phase timestamps the master reports;
  # nil when they are missing (a src job, a running build, or an older log).
  # The build phase is labelled by its slice (offline, or online/loopback when
  # the package is network-exempt).
  def build_split(job)
    return if job.online_at.blank? || job.build_at.blank? || job.stopped.blank?

    online = (Time.iso8601(job.build_at) - Time.iso8601(job.online_at)).to_i
    build = (Time.iso8601(job.stopped) - Time.iso8601(job.build_at)).to_i
    { online: duration_hms(online), build: duration_hms(build),
      slice: job.network == "full" ? "online" : (job.network.presence || "offline") }
  end

  # a build's length: "1h 12m", "4m 30s" or "45s"
  def duration_hms(seconds)
    return "-" if seconds.nil?

    h, rem = seconds.divmod(3600)
    m, sec = rem.divmod(60)
    return "#{h}h #{m}m" if h.positive?

    m.positive? ? "#{m}m #{sec}s" : "#{sec}s"
  end

  # a build's slice-transition marker line and which mode it announces:
  # archci-build installs dependencies online, then builds -- normally in the
  # offline slice (no network), or online/loopback for an exempt package.
  # Returns "online", "offline", "loopback", or nil for an ordinary line.
  def log_phase(line)
    return unless line.start_with?("==> Installing the dependencies", "==> Building in the archci-", "==> Building with ")
    return "offline" if line.include?("offline")
    return "loopback" if line.include?("loopback")

    "online"
  end

  # megabytes as archci top shows them
  def mem(mb)
    return "-" if mb.blank?

    mb = mb.to_f
    mb >= 1024 ? format("%.1fG", mb / 1024) : "#{mb.to_i}M"
  end

  def state_badge(state)
    tag.span(state, class: "badge badge-#{state}")
  end

  def nav_link(name, path, active)
    link_to name, path, class: active ? "active" : nil
  end
end
