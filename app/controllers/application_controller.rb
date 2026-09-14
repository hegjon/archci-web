# frozen_string_literal: true

class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  before_action :load_farm, unless: -> { %w[show stream].include?(action_name) && controller_name == "jobs" }

  rescue_from Farm::Unavailable do |e|
    @error = e.message
    render "shared/unavailable", status: :service_unavailable
  end

  private

  def load_farm
    @farm = Farm.current
    @repo = @farm.repo
    @generated = @farm.generated
  end

  # The queue commands (retry, requeue, enqueue) need the operator's password,
  # ARCHCI_WEB_PASSWORD; without one configured they are off.
  def require_operator
    password = ENV["ARCHCI_WEB_PASSWORD"]
    if password.blank?
      render plain: "the queue commands are off on this front end (ARCHCI_WEB_PASSWORD is not set)", status: :forbidden
      return
    end
    authenticate_or_request_with_http_basic("archci") do |_user, given|
      ActiveSupport::SecurityUtils.secure_compare(given.to_s, password)
    end
  end

  # one command to the master, then back to where the request came from
  def master_command(*args)
    out = Master.run(*args)
    Rails.cache.delete("farm/snapshot")
    redirect_back_or_to root_path, notice: out.strip.presence || "#{args.first} done"
  rescue Master::Error => e
    redirect_back_or_to root_path, alert: e.message
  end
end
