# frozen_string_literal: true

# Where a messenger sender links their account there to the Aixle account they
# are signed in to (docs/design/teams-integration.md §20, §21). The link the bot
# sent names the sender; the messenger's own sign-in it asks for must be them.
# Each messenger's controller says which link service, keys and labels it uses.
class Web::Integrations::ChatLinksController < Web::ApplicationController
  layout "inertia"

  def show
    claim = link.claim(params[:token])
    integration = claim && link.integration_for(claim)
    return render_link(state: "expired") if integration.nil?
    return render_link(state: "sign_in", login_url: login_path) unless signed_in?
    unless current_membership&.company_id == integration.company_id
      return render_link(state: "other_company", workspace: integration.company.name)
    end

    session[session_key] = params[:token]
    linked = ChatIdentity.exists?(provider: provider_key, workspace_id: claim[workspace_claim],
                                  external_user_id: claim[user_claim], user_id: current_user.id)
    render_link(state: linked ? "linked" : "ready", workspace: integration.company.name,
                sign_in_url: sign_in_path_for(params[:token]))
  end

  def sign_in
    claim = link.claim(params[:token])
    integration = claim && link.integration_for(claim)
    unless signed_in? && integration && current_membership&.company_id == integration.company_id
      return redirect_to(show_path_for(params[:token]))
    end

    # allow_other_host: the messenger's authorize URL, built from configuration and the signed link.
    redirect_to link.authorize_url(claim, current_user), allow_other_host: true
  end

  def complete
    state = Oauth::State.decode(params[:state])
    unless signed_in? && state&.dig("provider") == link::STATE_PROVIDER
      return redirect_to(back, alert: "This sign-in link is invalid or has expired")
    end
    return redirect_to(back, alert: "The sign-in was cancelled") if params[:error].present?

    side = Oauth::State.consume(state["nonce"])
    return redirect_to(back, alert: "This sign-in link was already used") if side.nil?

    complete_link(state, side)
    redirect_to back, notice: "Linked. Aixle Flow in #{messenger} now knows you as #{current_user.name}."
  rescue Teams::AccountLink::Refused, Slack::AccountLink::Refused, Teams::Error => e
    redirect_to back, alert: e.message
  end

  private

  def render_link(state:, **props)
    render inertia: "Integrations/ChatLink", props: {
      state: state, provider: provider_key, messenger: messenger, signInLabel: sign_in_label, account: account, **props
    }
  end

  def account
    return nil unless signed_in?

    { name: current_user.name, email: current_user.email }
  end

  def session_key = :"#{provider_key}_link_token"

  def back
    token = session[session_key]
    token.present? ? show_path_for(token) : root_path
  end
end
