# frozen_string_literal: true

# Enrolling and removing a person's own time-based one-time codes (CAP-4).
#
# TOTP is a STEP-UP method here: it proves possession of a device, not identity,
# so it never starts a session. A secret that has been generated but not yet
# verified is inert — `totp_confirmed_at` is what makes it live, so a half-
# finished enrolment cannot lock anybody out.
class Web::TotpController < Web::ApplicationController
  skip_before_action :enforce_onboarding
  before_action :require_signed_in

  # POST /totp — generate (or regenerate) an unconfirmed secret.
  def create
    return render(json: { error: "already_enabled" }, status: :conflict) if current_user.totp_enabled?

    current_user.totp_secret = ROTP::Base32.random
    current_user.save!

    render json: {
      provisioning_uri: current_user.totp_provisioning_uri(issuer: Settings.project_name),
      secret: current_user.totp_secret
    }
  end

  # POST /totp/confirm — a correct code is what turns it on.
  def confirm
    if current_user.verify_totp(params[:code])
      current_user.update!(totp_confirmed_at: Time.current)
      redirect_back fallback_location: root_path, notice: "Two-factor codes are on."
    else
      redirect_back fallback_location: root_path, inertia: { errors: { code: "That code did not match." } }
    end
  end

  # DELETE /totp
  def destroy
    current_user.update!(encrypted_totp_secret: nil, totp_confirmed_at: nil)
    redirect_back fallback_location: root_path, notice: "Two-factor codes are off."
  end

  private

  def require_signed_in
    redirect_to login_path unless signed_in?
  end
end
