# frozen_string_literal: true

# Signing in with a passkey (CAP-4).
#
# Anonymous by design: a discoverable credential tells us which account it
# belongs to, so there is no username step and no account-existence oracle.
class Web::PasskeySessionsController < Web::ApplicationController
  CHALLENGE_KEY = :passkey_authentication_challenge

  skip_before_action :enforce_company_auth_policy
  skip_before_action :enforce_onboarding
  skip_before_action :redirect_super_admin_to_admin_panel

  # POST /login/passkey/options
  def options
    options = WebAuthn::Credential.options_for_get(user_verification: "preferred")
    session[CHALLENGE_KEY] = options.challenge

    render json: options
  end

  # POST /login/passkey
  def create
    challenge = session.delete(CHALLENGE_KEY)
    return render(json: { error: "no_challenge" }, status: :unprocessable_entity) if challenge.blank?

    provider = IdentityProvider.deployment!("passkey")
    assertion = Auth::Registry.for(provider).complete(credential: credential_param, challenge: challenge)
    user = Auth::IdentityResolver.new(assertion, auto_join: false).resolve

    return render(json: { error: "account_deleted" }, status: :forbidden) if user.deleted?

    sign_in(user, provider: provider)
    render json: { ok: true, redirect_to: company_projects_path }
  rescue Auth::IdentityResolver::SuperAdminProviderError
    render json: { error: "super_admin_password_only" }, status: :forbidden
  rescue Auth::Method::Failure
    render json: { error: "passkey_rejected" }, status: :unprocessable_entity
  end

  private

  # WebAuthn's wire format is fixed camelCase — `rawId`, `clientDataJSON`,
  # `attestationObject`. This app underscores incoming keys, which silently turns
  # them into fields the gem cannot find, so the credential is exempted through
  # the documented opt-out.
  def preserved_param_paths
    [ [ :credential ] ]
  end

  # The exact assertion shape, not `permit!` — see the registration controller.
  def credential_param
    params.require(:credential).permit(
      :type, :id, :rawId, :authenticatorAttachment,
      response: [ :clientDataJSON, :authenticatorData, :signature, :userHandle ]
    ).to_h
  end
end
