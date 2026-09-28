# frozen_string_literal: true

module Auth
  # The port (AD-2). One adapter per method kind; adding a kind adds an adapter
  # and a row type, and does not edit a controller.
  class Method
    class Failure < StandardError; end

    attr_reader :provider

    def initialize(provider)
      @provider = provider
    end

    # @return [Auth::Assertion, nil] nil when the credentials do not check out
    def complete(**)
      raise NotImplementedError, "#{self.class.name} must implement #complete"
    end
  end
end
