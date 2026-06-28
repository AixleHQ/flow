# frozen_string_literal: true

# Reconciles (or removes) the Temporal Schedule backing a schedule TriggerBinding,
# off the request cycle so binding saves never spin up a Temporal client inline.
class ScheduleReconcileJob < ApplicationJob
  queue_as :default

  def perform(action, binding_id)
    case action.to_s
    when "reconcile"
      binding = TriggerBinding.find_by(id: binding_id)
      ScheduleReconciler.reconcile(binding) if binding
    when "remove"
      ScheduleReconciler.remove(binding_id)
    end
  end
end
