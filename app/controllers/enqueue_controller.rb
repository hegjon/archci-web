# frozen_string_literal: true

# `archci job enqueue PKGBASE 0 ARCH` from the browser: build a package now.
class EnqueueController < ApplicationController
  before_action :require_operator

  def create
    pkgbase = params[:pkgbase].to_s.strip
    arch = params[:arch].to_s.strip
    unless pkgbase.match?(/\A[A-Za-z0-9@._+-]+\z/) && arch.match?(/\A[a-z0-9_]+\z/)
      return redirect_back_or_to(root_path, alert: "enqueue needs a package name and an arch")
    end

    master_command("enqueue", pkgbase, "0", arch)
  end
end
