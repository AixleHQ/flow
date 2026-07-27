# frozen_string_literal: true

module CloudAuth
  # The user or their identity provider refused the authorization, or the portal
  # refused access to the requested role. Not recoverable by retrying.
  class DeniedError < Error; end
end
