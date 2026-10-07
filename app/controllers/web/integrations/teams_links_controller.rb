# frozen_string_literal: true

# Linking a Teams account: a Microsoft sign-in at the conversation's tenant
# (Teams::AccountLink), returning through the approval callback the app registers.
class Web::Integrations::TeamsLinksController < Web::Integrations::ChatLinksController
  private

  def link = Teams::AccountLink
  def provider_key = Chat::TeamsProvider::KEY
  def messenger = "Microsoft Teams"
  def sign_in_label = "Sign in with Microsoft to link"
  def workspace_claim = "tid"
  def user_claim = "oid"
  def show_path_for(token) = teams_link_path(token)
  def sign_in_path_for(token) = teams_link_sign_in_path(token)

  def complete_link(state, side)
    Teams::AccountLink.complete!(user: current_user, state: state, code: params[:code], code_verifier: side["code_verifier"])
  end
end
