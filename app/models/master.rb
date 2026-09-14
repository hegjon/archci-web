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

    def target = ENV.fetch("ARCHCI_MASTER", "archci@master")

    def ssh(*args)
      # commands reuse one kept-open connection, so a call costs a round trip,
      # not a handshake
      mux = [ "-o", "ControlMaster=auto", "-o", "ControlPersist=10m", "-o", "ControlPath=#{Rails.root.join('tmp', 'ssh-%C')}" ]
      out, err, status = Open3.capture3(*ssh_command(*mux), target, *args)
      raise Error, err.strip.presence || "ssh exited #{status.exitstatus}" unless status.success?

      out
    end

    def ssh_command(*extra)
      cmd = %w[ssh -o BatchMode=yes -o ConnectTimeout=10] + extra
      cmd += [ "-i", ENV["ARCHCI_SSH_KEY"], "-o", "IdentitiesOnly=yes" ] if ENV["ARCHCI_SSH_KEY"].present?
      cmd
    end
  end
end
