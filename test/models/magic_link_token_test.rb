# frozen_string_literal: true

require "test_helper"

class MagicLinkTokenTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, company: create(:company))
  end

  test "the plaintext token is returned once and never stored" do
    record, token = MagicLinkToken.issue!(@user)

    assert token.start_with?(MagicLinkToken::PREFIX)
    refute_equal token, record.token_digest
    assert_equal MagicLinkToken.digest(token), record.token_digest
  end

  test "a token works exactly once" do
    _record, token = MagicLinkToken.issue!(@user)

    assert_equal @user, MagicLinkToken.consume(token)
    assert_nil MagicLinkToken.consume(token)
  end

  test "an expired token is refused" do
    _record, token = MagicLinkToken.issue!(@user)

    travel (MagicLinkToken::TTL + 1.minute) do
      assert_nil MagicLinkToken.consume(token)
    end
  end

  test "an unknown token is refused without raising" do
    assert_nil MagicLinkToken.consume("aml_not-a-real-token")
    assert_nil MagicLinkToken.consume(nil)
  end

  test "the link dies with the account" do
    MagicLinkToken.issue!(@user)

    assert_difference "MagicLinkToken.count", -1 do
      @user.destroy!
    end
  end
end
