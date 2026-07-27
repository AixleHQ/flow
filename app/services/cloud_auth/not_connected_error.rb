# frozen_string_literal: true

module CloudAuth
  # The user has no cloud connection at all. Session-start preflight should have caught
  # this and offered a connect link, so reaching it from the vending endpoint means the
  # connection was removed mid-session.
  class NotConnectedError < Error; end
end
