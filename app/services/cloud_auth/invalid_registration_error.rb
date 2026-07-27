# frozen_string_literal: true

module CloudAuth
  # The stored OIDC client registration is unusable — most often because it aged past
  # the 90-day Identity Center limit. The fix is to register a new client and re-run
  # the device flow; refreshing cannot recover from this.
  class InvalidRegistrationError < Error; end
end
