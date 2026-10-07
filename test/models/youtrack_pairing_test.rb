# frozen_string_literal: true

require "test_helper"

class YoutrackPairingTest < ActiveSupport::TestCase
  setup do
    company = create(:company)
    @user = create(:user, company: company)
    @project = create(:project, company: company, owner: @user)
  end

  test "a pairing started in Aixle is approved for its project from the start; one started in YouTrack waits" do
    bound, = YoutrackPairing.start!(instance_url: "https://acme.youtrack.cloud", project: @project, user: @user)
    waiting, = YoutrackPairing.start!(instance_url: "https://acme.youtrack.cloud")

    assert_equal [ "aixle", "approved", @project.company, @user ], [ bound.origin, bound.state, bound.company, bound.user ]
    assert_equal [ "youtrack", "pending", nil ], [ waiting.origin, waiting.state, waiting.project ]
    assert_match(/\A[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}\z/, waiting.code)
  end

  test "only the secret authenticates it, and it is kept as a digest" do
    pairing, secret = YoutrackPairing.start!(instance_url: "https://acme.youtrack.cloud")

    assert pairing.authentic?(secret)
    assert_not pairing.authentic?("#{secret}x")
    assert_not pairing.authentic?(nil)
    assert_not_includes YoutrackPairing.where(id: pairing.id).pluck(:secret_digest).first, secret
  end

  test "a code is found however it is typed, only while its pairing waits in time" do
    pairing, = YoutrackPairing.start!(instance_url: "https://acme.youtrack.cloud")

    assert_equal pairing, YoutrackPairing.awaiting_code(" #{pairing.code.downcase.delete('-')} ")
    assert_nil YoutrackPairing.awaiting_code("ABCD")

    travel YoutrackPairing::EXPIRY + 1.second do
      assert_nil YoutrackPairing.awaiting_code(pairing.code)
      assert_equal "expired", pairing.state
    end

    pairing.approve!(project: @project, user: @user)
    assert_nil YoutrackPairing.awaiting_code(pairing.code)
    assert_equal [ "approved", @project.company ], [ pairing.state, pairing.company ]
  end
end
