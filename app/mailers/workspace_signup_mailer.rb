# frozen_string_literal: true

# The link that turns a filled-in signup form into a workspace. Opening it is
# what proves the person controls the address they claimed, so nothing exists
# until this mail is answered.
class WorkspaceSignupMailer < ApplicationMailer
  def confirm(email:, workspace_name:, token:)
    @workspace_name = workspace_name
    @url = confirm_workspace_url(token: token)
    @ttl_hours = (WorkspaceSignupTicket::TTL / 3600).to_i

    mail(to: email, subject: "Confirm your Aixle Flow workspace")
  end
end
