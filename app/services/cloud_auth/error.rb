# frozen_string_literal: true

module CloudAuth
  # Base for every cloud-connection failure. Callers rescue these, never vendor
  # SDK exception classes.
  class Error < StandardError; end
end
