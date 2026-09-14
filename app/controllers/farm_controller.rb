# frozen_string_literal: true

# The front page: the farm as archci top shows it.
class FarmController < ApplicationController
  def show
    @newest_failed = @farm.failed.first(20)
  end
end
