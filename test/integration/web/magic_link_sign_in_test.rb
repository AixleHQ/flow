# frozen_string_literal: true

require "test_helper"

# CAP-4: emailed single-use sign-in links.
class Web::MagicLinkSignInTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :onboarding_completed, company: @company)
    @provider = IdentityProvider.deployment!("magic_link")
    # The company seeder already gave this company a row for every deployment
    # provider (AD-4), so take that one rather than creating a duplicate.
    @policy = CompanyAuthPolicy.find_by!(company: @company, identity_provider: @provider)
  end

  def request_link
    perform_enqueued_jobs do
      post request_magic_link_path, params: { email: @user.email }
    end
    MagicLinkToken.order(:id).last
  end

  test "requesting a link emails one and says nothing about whether the address exists" do
    assert_difference "MagicLinkToken.count", 1 do
      post request_magic_link_path, params: { email: @user.email }
    end
    assert_redirected_to login_path(sent: "1")

    # Same answer for an address that does not exist: the response must not
    # become an account-existence oracle.
    assert_no_difference "MagicLinkToken.count" do
      post request_magic_link_path, params: { email: "nobody@#{@company.email_domain}" }
    end
    assert_redirected_to login_path(sent: "1")
  end

  test "opening the link does NOT consume it — mail scanners fetch every URL" do
    post request_magic_link_path, params: { email: @user.email }
    token_record = MagicLinkToken.order(:id).last

    get magic_link_path(token: "aml_whatever")

    assert_response :success
    assert_nil token_record.reload.consumed_at
  end

  test "confirming the link signs the person in, exactly once" do
    post request_magic_link_path, params: { email: @user.email }
    record = MagicLinkToken.order(:id).last
    # The plaintext never leaves #issue!, so re-issue one we can post.
    record.destroy!
    _fresh, token = MagicLinkToken.issue!(@user)

    post confirm_magic_link_path(token: token)

    assert_redirected_to company_projects_path
    assert UserSession.live.exists?(user: @user)
    assert_includes UserSession.live.find_by(user: @user).proved_provider_ids, @provider.id

    # Replayed: the link is spent.
    delete logout_path
    post confirm_magic_link_path(token: token)
    assert_redirected_to login_path(error: "magic_link_invalid")
  end

  test "a company that does not accept magic links is not sent one" do
    @policy.update!(enabled: false)

    assert_no_difference "MagicLinkToken.count" do
      post request_magic_link_path, params: { email: @user.email }
    end
  end
end
