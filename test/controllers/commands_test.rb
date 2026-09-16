require "test_helper"

class CommandsTest < ActionDispatch::IntegrationTest
  ID = "5-1788893881-hegjon-test,grub,2:2.14-1,x86_64"

  test "the queue commands are off without a password" do
    ENV["ARCHCI_WEB_PASSWORD"] = nil
    post retry_job_path(ID)
    assert_response :forbidden
    assert_equal [], FakeMaster.calls.select { |c| c.first == "retry" }
  end

  test "the queue commands need the operator's password" do
    ENV["ARCHCI_WEB_PASSWORD"] = "s3cret"
    post retry_job_path(ID)
    assert_response :unauthorized
    post retry_job_path(ID), headers: basic("wrong")
    assert_response :unauthorized
    post retry_job_path(ID), headers: basic("s3cret")
    assert_redirected_to job_path("0-1790000000-#{ID.split('-', 3).last}".tr(",", "/"))   # a retry is a new job: its page
    assert_includes FakeMaster.calls, [ "retry", ID ]
    post requeue_job_path(ID), headers: basic("s3cret")
    assert_includes FakeMaster.calls, [ "requeue", ID ]
    post enqueue_path, params: { pkgbase: "acl", arch: "x86_64" }, headers: basic("s3cret")
    assert_includes FakeMaster.calls, [ "enqueue", "acl", "0", "x86_64" ]
    post enqueue_path, params: { pkgbase: "acl; rm", arch: "x86_64" }, headers: basic("s3cret")
    assert_not FakeMaster.calls.any? { |c| c.first == "enqueue" && c[1] != "acl" }
  ensure
    ENV["ARCHCI_WEB_PASSWORD"] = nil
  end

  private

  def basic(password)
    { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("operator", password) }
  end
end
