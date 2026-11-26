# frozen_string_literal: true

module AwsOidc
  # STS could not fetch the issuer's discovery document or keys.
  class IssuerUnreachableError < Error; end
end
