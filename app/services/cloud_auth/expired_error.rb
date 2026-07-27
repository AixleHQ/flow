# frozen_string_literal: true

module CloudAuth
  # The device code, access token, or Identity Center session is no longer valid.
  # Recoverable by re-running the connect flow.
  class ExpiredError < Error; end
end
