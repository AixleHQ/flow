# frozen_string_literal: true

require "test_helper"

class Middleware::NullByteGuardTest < ActiveSupport::TestCase
  APP = ->(_env) { [ 200, {}, [ "ok" ] ] }

  def status_for(path)
    Middleware::NullByteGuard.new(APP).call(Rack::MockRequest.env_for(path)).first
  end

  test "a NUL byte in the path or the query string is a bad request" do
    assert_equal 400, status_for("/webhooks/in/%00")
    assert_equal 400, status_for("/share/abc%00def")
    assert_equal 400, status_for("/projects?q=a%00b")
  end

  test "requests without a NUL byte reach the app" do
    assert_equal 200, status_for("/webhooks/in/slack-team-T1")
    assert_equal 200, status_for("/search?q=100%25")
    assert_equal 200, status_for("/files/%2500")
  end
end
