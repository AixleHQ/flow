# frozen_string_literal: true

module AwsOidc
  # The role's trust policy rejected the subject, or lacks sts:TagSession.
  class TrustPolicyError < Error; end
end
