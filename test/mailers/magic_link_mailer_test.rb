# frozen_string_literal: true

require "test_helper"

class MagicLinkMailerTest < ActionMailer::TestCase
  include MailerAssertions

  setup do
    @user = create(:user, company: create(:company))
  end

  test "it sends the sign-in link to the user" do
    _record, token = MagicLinkToken.issue!(@user)

    mail = MagicLinkMailer.sign_in(@user, token)

    assert_equal [ @user.email ], mail.to
    href = Nokogiri::HTML(mail.html_part.decoded).at_css("a[role=button]")["href"]
    assert href.start_with?("http"), "expected an absolute URL, got #{href.inspect}"
    assert_includes href, token
  end

  test "every line of the email is readable on the layout's dark background" do
    _record, token = MagicLinkToken.issue!(@user)

    assert_every_text_coloured MagicLinkMailer.sign_in(@user, token)
  end
end
