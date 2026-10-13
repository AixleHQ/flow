# frozen_string_literal: true

class FakeMemorySourceVerifier
  attr_accessor :current

  def initialize(current: true)
    @current = current
  end

  def current?(project:, sources:)
    current
  end
end
