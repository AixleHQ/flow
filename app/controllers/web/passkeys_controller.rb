# frozen_string_literal: true

# Registering and removing a person's own passkeys (AD-18).
#
# The credential belongs to the user: no company-admin surface touches these
# actions, and a company that stops accepting passkeys never deletes one.
class Web::PasskeysController < Web::ApplicationController
  CHALLENGE_KEY = :passkey_registration_challenge

  skip_before_action :enforce_onboarding
  before_action :require_signed_in

  # POST /passkeys/options
  def options
    options = WebAuthn::Credential.options_for_create(
      user: { id: current_user.webauthn_handle, name: current_user.email, display_name: current_user.name },
      exclude: current_user.webauthn_credentials.pluck(:external_id),
      # Discoverable ("resident") credentials are what make a passkey usable
      # without typing a username first.
      authenticator_selection: { resident_key: "required", user_verification: "preferred" }
    )
    session[CHALLENGE_KEY] = options.challenge

    render json: options
  end

  # POST /passkeys
  def create
    challenge = session.delete(CHALLENGE_KEY)
    return render(json: { error: "no_challenge" }, status: :unprocessable_entity) if challenge.blank?

    webauthn_credential = WebAuthn::Credential.from_create(credential_param)
    webauthn_credential.verify(challenge)

    current_user.webauthn_credentials.create!(
      external_id: webauthn_credential.id,
      public_key: webauthn_credential.public_key,
      sign_count: webauthn_credential.sign_count,
      nickname: params[:nickname].presence
    )
    render json: { ok: true }
  rescue WebAuthn::Error => e
    render json: { error: e.class.name.demodulize.underscore }, status: :unprocessable_entity
  end

  # DELETE /passkeys/:id
  def destroy
    credential = current_user.webauthn_credentials.find(params[:id])
    credential.destroy!
    redirect_back fallback_location: root_path, notice: "Passkey removed."
  end

  private

  def require_signed_in
    redirect_to login_path unless signed_in?
  end

  # WebAuthn's wire format is fixed camelCase — `rawId`, `clientDataJSON`,
  # `attestationObject`. This app underscores incoming keys, which silently turns
  # them into fields the gem cannot find, so the credential is exempted through
  # the documented opt-out.
  def preserved_param_paths
    [ [ :credential ] ]
  end

  # The exact registration shape, not `permit!`: the WebAuthn wire format is
  # fixed, so enumerating it costs nothing and keeps an unexpected key from
  # reaching the gem.
  def credential_param
    params.require(:credential).permit(
      :type, :id, :rawId, :authenticatorAttachment,
      response: [ :clientDataJSON, :attestationObject, { transports: [] } ]
    ).to_h
  end
end
