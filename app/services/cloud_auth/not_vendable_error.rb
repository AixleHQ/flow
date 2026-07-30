# frozen_string_literal: true

module CloudAuth
  # The connection exists but needs no server-side credential vending — a bearer-token
  # or static-key connection already puts everything the container needs in its env.
  class NotVendableError < Error; end
end
