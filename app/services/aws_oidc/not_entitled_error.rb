# frozen_string_literal: true

module AwsOidc
  # The session may not have this role: not an active workflow step, or the role is
  # not attached to its step.
  class NotEntitledError < Error; end
end
