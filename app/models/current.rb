# frozen_string_literal: true

# What the auth layer established for this request, for code with no request of
# its own to ask: ContainerTicket binds a pass to the signed-in browser it was
# issued to, so ending that sign-in ends the pass, and a password change keeps
# the browser it was made from signed in.
#
# `feature_snapshot` is the flag values read by the first `Feature.enabled?` of
# this request or job (FeatureFlags.snapshot).
#
# `analytics_actor` and `analytics_via` are who is acting and through what
# (Analytics::VIAS), set by the web and MCP entry points so a model change made
# from either reports the same event. `analytics_origin` narrows a creation
# down further (a template install, the builder).
class Current < ActiveSupport::CurrentAttributes
  attribute :user_session
  attribute :feature_snapshot
  attribute :analytics_actor, :analytics_via, :analytics_origin
end
