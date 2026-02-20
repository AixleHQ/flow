# frozen_string_literal: true

module StateEventConcern
  extend ActiveSupport::Concern

  included do
    def available_events(attribute = nil)
      aasm(attribute).events(permitted: true).map(&:name).map(&:to_s)
    end

    def available_states(attribute = nil)
      aasm(attribute).states.map(&:name).map(&:to_s)
    end
  end

  class_methods do
    def aasm(attribute, *args)
      define_event_method(attribute)
      super
    end

    def define_event_method(attribute)
      setter_name = :"#{attribute}_event="
      return if instance_methods.include?(setter_name)

      define_method(setter_name) do |value|
        return if value.blank?

        machine = aasm(attribute)
        machine.fire(value) if machine.may_fire_event?(value.to_sym)
      end

      getter_name = :"#{attribute}_event"
      define_method(getter_name) do
        aasm(attribute).current_state
      end
    end
  end
end
