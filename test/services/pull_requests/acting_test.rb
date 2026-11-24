# frozen_string_literal: true

require "test_helper"

class PullRequests::ActingTest < ActiveSupport::TestCase
  setup do
    @calls = 0
    @acting = PullRequests::Acting.new(user_id: 7) do
      @calls += 1
      { login: "octo-user", token: "ghu_person" }
    end
  end

  test "inspect and to_s of an unresolved Acting do not run the resolver" do
    assert_equal "#<PullRequests::Acting user_id=7>", @acting.inspect
    assert_equal "#<PullRequests::Acting user_id=7>", @acting.to_s
    assert_equal "#{@acting}", @acting.to_s
    assert_equal 0, @calls
  end

  test "inspect shows the login once resolved and never the token" do
    @acting.token

    assert_equal 1, @calls
    assert_includes @acting.inspect, "login=\"octo-user\""
    assert_not_includes @acting.inspect, "ghu_person"
    assert_equal 1, @calls
  end

  test "login and token resolve once" do
    2.times { @acting.login && @acting.token }

    assert_equal 1, @calls
  end

  test "a failed resolution is not remembered" do
    attempts = 0
    acting = PullRequests::Acting.new(user_id: 7) do
      attempts += 1
      raise PullRequests::Error, "refused" if attempts == 1

      { login: "x", token: "t" }
    end

    assert_raises(PullRequests::Error) { acting.token }
    assert_equal "t", acting.token
  end
end
