# frozen_string_literal: true

module Runners
  # An action that makes no sense for a runner type, such as Rebuild on a
  # `manual` runner (docs/design/agent-runtimes/runner-coder.md §7.4). The UI
  # hides the action by the type's capabilities, so a user does not reach it.
  class UnsupportedOperation < StandardError; end
end
