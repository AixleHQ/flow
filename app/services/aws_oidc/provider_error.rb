# frozen_string_literal: true

module AwsOidc
  # Anything else: throttling, an outage, the network.
  class ProviderError < Error; end
end
