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

  # how long the build ran, from the archci-build start and finish lines the
  # log carries ("... on <worker> at <ts>" and "... finished with N at <ts>"):
  # "1h 12m" or "4m 30s"; nil if either line is missing (e.g. an old log)
  def build_time(lines)
    return if lines.blank?

    stamp = ->(line) { line && line[/ at (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)/, 1] }
    start = stamp.call(lines.find { |l| l.start_with?("==> archci-build") && l.include?(" on ") && l.include?(" at ") })
    finish = stamp.call(lines.reverse_each.find { |l| l.start_with?("==> archci-build finished with") })
    return unless start && finish

    duration_hms((Time.iso8601(finish) - Time.iso8601(start)).to_i)
  end

  # a build's length: "1h 12m", "4m 30s" or "45s"
  def duration_hms(seconds)
    return "-" if seconds.nil?

    h, rem = seconds.divmod(3600)
    m, sec = rem.divmod(60)
    return "#{h}h #{m}m" if h.positive?

    m.positive? ? "#{m}m #{sec}s" : "#{sec}s"
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
