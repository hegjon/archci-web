# frozen_string_literal: true

require "open3"

# The master, reached over ssh as the web key: one command per call, its
# stdout back. The key is authorized on the master with `archci authorize
# --web`, so it can run exactly what archci-shell's web role allows:
# snapshot, log ID, retry ID, requeue ID, enqueue PKGBASE PRIO ARCH.
#
# ARCHCI_MASTER   the ssh destination (default archci@master)
# ARCHCI_SSH_KEY  the web key (default: ssh's own choice)
#
# One ssh connection is kept open (ControlMaster) so a call costs a round
# trip, not a handshake. Tests replace Master.runner with a fake.
class Master
  class Error < StandardError; end

  class << self
    attr_writer :runner

    def runner
      @runner ||= method(:ssh)
    end

    # the command's stdout, or Master::Error with ssh's or the master's message
    def run(*args)
      runner.call(*args)
    end

    # a long-running command's stdout, line by line, until it ends or the
    # block's reader is gone (`follow ID`); ssh is killed when the block leaves
    def stream(*args, &block)
      streamer.call(*args, &block)
    end

    attr_writer :streamer

    def streamer
      @streamer ||= method(:ssh_stream)
    end

    def target = ENV.fetch("ARCHCI_MASTER", "archci@master")

    def ssh(*args)
      # the quick commands (snapshot, log) reuse one kept-open connection, so
      # a call costs a round trip, not a handshake
      mux = [ "-o", "ControlMaster=auto", "-o", "ControlPersist=10m", "-o", "ControlPath=#{Rails.root.join('tmp', 'ssh-%C')}" ]
      out, err, status = Open3.capture3(*ssh_command(*mux), target, *args)
      raise Error, err.strip.presence || "ssh exited #{status.exitstatus}" unless status.success?

      out
    end

    # follow: a connection of its own (a multiplexed session ends the remote
    # command before its output flows), open for as long as the reader wants
    def ssh_stream(*args)
      Open3.popen3(*ssh_command, target, *args) do |stdin, stdout, stderr, thread|
        # stdin stays open (closing it makes ssh, with no pty, end the remote
        # command early); the master's follow stops when the job ends, and we
        # kill ssh below when the reader leaves
        stdout.each_line { |line| yield line.chomp }
        raise Error, stderr.read.strip.presence || "ssh exited #{thread.value.exitstatus}" unless thread.value.success?
      ensure
        stdin.close rescue nil # rubocop:disable Style/RescueModifier
        Process.kill("TERM", thread.pid) rescue nil # rubocop:disable Style/RescueModifier
      end
    end

    def ssh_command(*extra)
      cmd = %w[ssh -o BatchMode=yes -o ConnectTimeout=10] + extra
      cmd += [ "-i", ENV["ARCHCI_SSH_KEY"], "-o", "IdentitiesOnly=yes" ] if ENV["ARCHCI_SSH_KEY"].present?
      cmd
    end
  end
end
