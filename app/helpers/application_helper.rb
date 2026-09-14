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

  # megabytes as archci top shows them
  def mem(mb)
    return "-" if mb.blank?

    mb = mb.to_f
    mb >= 1024 ? format("%.1fG", mb / 1024) : "#{mb.to_i}M"
  end

  def state_badge(state)
    tag.span(state, class: "badge badge-#{state}")
  end

  # a colored glyph for a job's state, for scanning the tree
  STATUS_GLYPH = { "done" => "\u2714", "failed" => "\u2718", "running" => "\u25CF", "pending" => "\u25CB" }.freeze
  def status_symbol(state)
    tag.span(STATUS_GLYPH.fetch(state, "\u00B7"), class: "sym sym-#{state}", title: state)
  end

  # one glyph for a package row, attention first: a failure, then a running
  # build, then something waiting, else all done
  def package_status(jobs)
    states = jobs.map(&:state)
    st = %w[failed running pending done].find { |s| states.include?(s) } || "done"
    status_symbol(st)
  end

  def nav_link(name, path, active)
    link_to name, path, class: active ? "active" : nil
  end
end
