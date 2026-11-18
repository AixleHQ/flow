# frozen_string_literal: true

module MCPAuth
  # The client is unknown or may not use the redirect URI it sent. Shown on the
  # authorize page itself: redirecting would hand the error to a party we could
  # not identify.
  class InvalidClient < StandardError; end
end
