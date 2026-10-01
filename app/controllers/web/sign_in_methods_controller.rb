# frozen_string_literal: true

# Linking Google or Microsoft to the signed-in account, and removing a linked
# method — the way in a refused sign-in (`link_required`) points people to.
#
# There is no separate recent-sign-in check: like every page, these sit behind
# the company entry gate (AD-5), so only a session holding a proof its current
# company accepts gets here, and anything less is sent to step-up first.
class Web::SignInMethodsController < Web::ApplicationController
  OMNIAUTH_REQUEST_PATHS = { "google" => "/auth/google", "microsoft" => "/auth/microsoft" }.freeze

  before_action :require_signed_in
  before_action :refuse_impersonation

  # POST /profile/sign_in_methods — completed by Web::SessionsController#omniauth.
  def create
    kind = params[:kind].to_s
    unless Auth::SignInMethods.linkable?(current_user, kind)
      return redirect_to(security_profile_path, alert: "That sign-in method cannot be linked to your account.")
    end

    Auth::LinkIntent.start(session, user_session: current_user_session, kind: kind)
    # 307 makes the browser repeat this POST, authenticity token included.
    # OmniAuth's request phase accepts nothing else (CVE-2015-9284), and a 302
    # would turn it into a GET.
    redirect_to OMNIAUTH_REQUEST_PATHS.fetch(kind), status: :temporary_redirect
  end

  # DELETE /profile/sign_in_methods/:id
  def destroy
    identity = current_user.user_identities.includes(:identity_provider).find(params[:id])
    Auth::SignInMethods.remove!(current_user, identity)
    redirect_to security_profile_path, notice: "#{identity.identity_provider.display_name} removed from your sign-in methods."
  rescue Auth::SignInMethods::RemovalRefused => e
    redirect_to security_profile_path, alert: e.message
  end

  private

  def require_signed_in
    redirect_to login_path unless signed_in?
  end

  # A method linked during an impersonation would let the operator sign in as
  # that person later without impersonating, outside its audit trail.
  def refuse_impersonation
    return unless impersonated?

    redirect_to security_profile_path, alert: "Sign-in methods cannot be changed while impersonating."
  end
end
