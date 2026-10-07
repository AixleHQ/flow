# frozen_string_literal: true

# Where a Teams sender links their Teams account to the Aixle account they are
# signed in to (docs/design/teams-integration.md §20). The link the bot sent
# names the Teams account; the Microsoft sign-in it asks for must be that one.
class Web::Integrations::TeamsLinksController < Web::ApplicationController
  layout "inertia"

  def show
    claim = Teams::AccountLink.claim(params[:token])
    integration = claim && Teams::AccountLink.integration_for(claim)
    return render_link(state: "expired") if integration.nil?
    return render_link(state: "sign_in", login_url: login_path) unless signed_in?
    unless current_membership&.company_id == integration.company_id
      return render_link(state: "other_company", workspace: integration.company.name)
    end

    session[:teams_link_token] = params[:token]
    linked = ChatIdentity.exists?(provider: Chat::TeamsProvider::KEY, workspace_id: claim["tid"],
                                  external_user_id: claim["oid"], user_id: current_user.id)
    render_link(state: linked ? "linked" : "ready", workspace: integration.company.name,
                sign_in_url: teams_link_sign_in_path(params[:token]))
  end

  def sign_in
    claim = Teams::AccountLink.claim(params[:token])
    integration = claim && Teams::AccountLink.integration_for(claim)
    unless signed_in? && integration && current_membership&.company_id == integration.company_id
      return redirect_to(teams_link_path(params[:token]))
    end

    # allow_other_host: Microsoft's authorize URL, built from configuration and the signed link.
    redirect_to Teams::AccountLink.authorize_url(claim, current_user), allow_other_host: true
  end

  # Reached from the approval callback, the one redirect the app registers.
  def complete
    state = Oauth::State.decode(params[:state])
    unless signed_in? && state&.dig("provider") == Teams::AccountLink::STATE_PROVIDER
      return redirect_to(back, alert: "This Microsoft sign-in link is invalid or has expired")
    end
    return redirect_to(back, alert: "Microsoft sign-in was cancelled") if params[:error].present?

    side = Oauth::State.consume(state["nonce"])
    return redirect_to(back, alert: "This Microsoft sign-in link was already used") if side.nil?

    Teams::AccountLink.complete!(user: current_user, state: state, code: params[:code], code_verifier: side["code_verifier"])
    redirect_to back, notice: "Linked. Aixle Flow in Teams now knows you as #{current_user.name}."
  rescue Teams::AccountLink::Refused, Teams::Error => e
    redirect_to back, alert: e.message
  end

  private

  def render_link(state:, **props)
    render inertia: "Integrations/TeamsLink", props: { state: state, account: account, **props }
  end

  def account
    return nil unless signed_in?

    { name: current_user.name, email: current_user.email }
  end

  def back
    token = session[:teams_link_token]
    token.present? ? teams_link_path(token) : root_path
  end
end
