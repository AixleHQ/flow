# frozen_string_literal: true

module ContainerRuntime
  class CapacityError < StandardError
    attr_reader :reason
    def initialize(message, reason: "cluster_capacity")
      @reason = reason
      super(message)
    end
  end
end
