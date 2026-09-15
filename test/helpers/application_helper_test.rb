# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "log_phase marks archci-build's slice transitions and nothing else" do
    assert_equal "online", log_phase("==> Installing the dependencies (with the network)")
    assert_equal "offline", log_phase("==> Building in the archci-offline slice")
    assert_equal "online", log_phase("==> Building in the archci-online slice")
    assert_equal "loopback", log_phase("==> Building in the archci-loopback slice")
    assert_equal "online", log_phase("==> Building with the network: the package is exempt (package.json)")
    assert_equal "loopback", log_phase("==> Building with loopback: the package talks to itself (package.json)")
    assert_nil log_phase("==> Starting build()...")
    assert_nil log_phase("  Compiling starship v1.26.0")
  end
end
