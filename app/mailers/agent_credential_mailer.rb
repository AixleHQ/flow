# frozen_string_literal: true

# Re-authentication notices for agent CLI credentials.
#
# An OAuth integration that stops refreshing has told its owner since oauth-unification
# §4.6 (OauthMailer). An agent login that stops refreshing told nobody: the row flipped to
# `status: error`, the profile badge went on reading "Connected", and the user found out
# when a workflow run came back empty. This closes that gap.
class AgentCredentialMailer < ApplicationMailer
  # Sent once, when the credential is escalated to error — either after
  # MAX_REFRESH_FAILURES consecutive failures or immediately on a rejection the vendor
  # says is permanent. Re-authenticating is the only remedy at that point.
  def refresh_failed(credential)
    @agent_name = credential.agent_type.titleize
    @reason = credential.refresh_error
    @profile_url = profile_url(host: Settings.domain, protocol: Settings.protocol)

    mail(to: credential.user.email, subject: "Action needed: sign in to #{@agent_name} again")
  end
end
