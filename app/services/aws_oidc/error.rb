# frozen_string_literal: true

module AwsOidc
  # Every failure of an AWS OIDC exchange, translated from STS so callers and the UI
  # never see vendor classes (docs/design/aws-oidc-integration.md §9).
  class Error < StandardError
    attr_reader :aws_code

    def initialize(message = nil, aws_code: nil)
      super(message)
      @aws_code = aws_code
    end
  end
end
