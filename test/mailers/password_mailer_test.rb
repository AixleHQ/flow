# frozen_string_literal: true

require "test_helper"

class PasswordMailerTest < ActionMailer::TestCase
  setup do
    @user = create(:user, email: "reset-me@example.com", password: AuthHelper::TEST_PASSWORD)
  end

  test "the reset email carries a link that resolves to its owner and states its lifetime" do
    email = PasswordMailer.reset(@user)

    assert_equal [ "reset-me@example.com" ], email.to
    body = email.text_part.decoded
    assert_includes body, "expires in 60 minutes"
    token = CGI.unescape(body[%r{/password/reset/([^\s"]+)}, 1])
    assert_equal @user, User.find_by_password_reset_token(token)
  end

  test "the notice names what happened and links to a reset" do
    { "set" => "A password was set", "changed" => "was changed", "reset" => "was reset" }.each do |event, phrase|
      email = PasswordMailer.updated(@user, event)

      assert_equal [ "reset-me@example.com" ], email.to
      assert_includes email.text_part.decoded, phrase
      assert_includes email.text_part.decoded, "/password/reset?email=reset-me%40example.com"
    end
  end
end
