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
    unless linkable?(integration)
      return render_link(state: "other_company", workspace: linkable_company_names(integration))
    end

    session[session_key] = params[:token]
    linked = ChatIdentity.exists?(provider: provider_key, workspace_id: claim[workspace_claim],
                                  external_user_id: claim[user_claim], user_id: current_user.id)
    render_link(state: linked ? "linked" : "ready", workspace: current_membership.company.name,
                sign_in_url: sign_in_path_for(params[:token]))
  end

  def sign_in
    claim = link.claim(params[:token])
    integration = claim && link.integration_for(claim)
    unless signed_in? && integration && linkable?(integration)
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

  # Any company of the person's that connected the workspace may link them, as
  # long as it is the one they are working in.
  def linkable?(integration)
    current_membership.present? && integration.chat_peers.exists?(company_id: current_membership.company_id)
  end

  # Only the person's own companies are named: the others that connected the
  # same workspace stay unseen (docs/design/shared-chat-workspaces.md, decision 17).
  def linkable_company_names(integration)
    names = Company.where(id: current_user.company_memberships.active.select(:company_id))
                   .where(id: integration.chat_peers.select(:company_id)).order(:name).pluck(:name)
    names.to_sentence(two_words_connector: " or ", last_word_connector: " or ").presence || "a company that connected it"
  end

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
