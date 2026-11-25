# frozen_string_literal: true

module AwsOidc
  # The request is invalid for this role, e.g. a duration above its maximum.
  class RoleConfigurationError < Error; end
end
