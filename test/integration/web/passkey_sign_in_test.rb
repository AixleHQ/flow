# frozen_string_literal: true

require "test_helper"
require "webauthn/fake_client"

# CAP-4: passkeys. A real WebAuthn ceremony against the gem's fake
# authenticator — the signature path is the whole security value, so a test that
# stubbed the verification would prove nothing.
class Web::PasskeySignInTest < ActionDispatch::IntegrationTest
  setup do
    @origin = "#{Settings.protocol}://#{Settings.domain}"
    @client = WebAuthn::FakeClient.new(@origin)
    @company = create(:company)
    @user = create(:user, :onboarding_completed, company: @company,
                          password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    @provider = IdentityProvider.deployment!("passkey")
  end

  def register_passkey
    sign_in_as(@user)
    post passkey_options_path
    challenge = JSON.parse(response.body)["challenge"]
    credential = @client.create(challenge: challenge)

    post passkeys_path, params: { credential: credential, nickname: "Laptop" }, as: :json
    @user.webauthn_credentials.order(:id).last
  end

  test "a person registers a passkey on their own account" do
    assert_difference "WebauthnCredential.count", 1 do
      register_passkey
    end

    assert_response :success
    assert_equal "Laptop", @user.webauthn_credentials.last.nickname
  end

  test "a registered passkey signs its owner in with no password" do
    register_passkey
    delete logout_path

    post passkey_login_options_path
    challenge = JSON.parse(response.body)["challenge"]
    assertion = @client.get(challenge: challenge)

    post passkey_login_path, params: { credential: assertion }, as: :json

    assert_response :success
    assert UserSession.live.exists?(user: @user)
    assert_includes UserSession.live.find_by(user: @user).proved_provider_ids, @provider.id
  end

  test "an assertion with no matching challenge is refused" do
    register_passkey
    delete logout_path

    post passkey_login_path, params: { credential: { id: "x", rawId: "x", type: "public-key", response: {} } },
                             as: :json

    assert_response :unprocessable_entity
    refute UserSession.live.exists?(user: @user)
  end

  test "a company disabling passkeys does not delete anybody's passkey" do
    # AD-18: the credential belongs to the person and works elsewhere; the
    # company only declines to accept it for entry here.
    credential = register_passkey
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @provider).update!(enabled: false)

    assert WebauthnCredential.exists?(credential.id)
    assert_equal 1, @user.reload.webauthn_credentials.count
  end

  test "a person can remove their own passkey" do
    credential = register_passkey

    assert_difference "WebauthnCredential.count", -1 do
      delete passkey_path(credential)
    end
  end
end
