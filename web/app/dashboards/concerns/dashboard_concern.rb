# frozen_string_literal: true

module DashboardConcern
  extend ActiveSupport::Concern

  class_methods do
    def available_events_collection(field, state_column = :state)
      field.resource.available_events(state_column).map { |event| [ event.humanize, event ] }
    rescue NoMethodError
      []
    end

    def available_states_collection(field, state_column = :state)
      model_class = field.resource.class
      # Try enumerize first (our models use enumerize)
      if model_class.respond_to?(state_column) && model_class.public_send(state_column).respond_to?(:values)
        model_class.public_send(state_column).values.map { |state| [ state.humanize, state ] }
      # Fallback to AASM if available
      elsif model_class.respond_to?(:aasm) && model_class.aasm(state_column).states.any?
        model_class.aasm(state_column).states.map { |state| [ state.name.humanize, state.name.to_s ] }
      else
        []
      end
    rescue NoMethodError
      []
    end
  end
end
