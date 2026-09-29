# frozen_string_literal: true

# What the auth layer established for this request, for code with no request of
# its own to ask: ContainerTicket binds a pass to the signed-in browser it was
# issued to, so ending that sign-in ends the pass.
class Current < ActiveSupport::CurrentAttributes
  attribute :user_session
end
