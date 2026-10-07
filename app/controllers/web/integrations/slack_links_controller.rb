# frozen_string_literal: true

# Linking a Slack account: Sign in with Slack in that workspace (Slack::AccountLink).
class Web::Integrations::SlackLinksController < Web::Integrations::ChatLinksController
  private

  def link = Slack::AccountLink
  def provider_key = Chat::SlackProvider::KEY
  def messenger = "Slack"
  def sign_in_label = "Sign in with Slack to link"
  def workspace_claim = "team"
  def user_claim = "user"
  def show_path_for(token) = slack_link_path(token)
  def sign_in_path_for(token) = slack_link_sign_in_path(token)

  def complete_link(state, side)
    Slack::AccountLink.complete!(user: current_user, state: state, code: params[:code], nonce: side["code_verifier"])
  end
end
