# frozen_string_literal: true

# What the auth layer established for this request, for code with no request of
# its own to ask: ContainerTicket binds a pass to the signed-in browser it was
# issued to, so ending that sign-in ends the pass, and a password change keeps
# the browser it was made from signed in.
#
# `feature_snapshot` is the flag values the first `Feature.enabled?` of this
# request or job saw, so one unit of work gets one answer per flag
# (FeatureFlags.snapshot).
class Current < ActiveSupport::CurrentAttributes
  attribute :user_session
  attribute :feature_snapshot
end
