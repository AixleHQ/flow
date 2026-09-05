# frozen_string_literal: true

# The one path that turns the queue on, used by both the rake task and the
# admin page so they cannot drift apart.
#
# First activation has two gates. The database gate lives in
# SessionAdmissionPolicy.sync! (nothing may still be running). The runtime gate
# lives here, because only the worker can see the runtime — and it has to be a
# gate rather than a warning: a Pod left over from the legacy launch path
# answers to no reservation, so the queue would hand out capacity that is
# already spent.
class SessionAdmissionActivation
  Refused = Class.new(StandardError)

  # Enough to recognise what is left without printing a cluster.
  SAMPLE = 5

  def self.call
    verify_runtime_drained! unless SessionAdmissionPolicy.current.enabled?
    SessionAdmissionPolicy.sync!
  end

  def self.verify_runtime_drained!
    remaining = SessionRuntimeInventory.fetch
    return if remaining.empty?

    sample = remaining.first(SAMPLE).join(", ")
    sample += " (+#{remaining.size - SAMPLE} more)" if remaining.size > SAMPLE
    raise Refused, "Legacy runtime resources remain; drain and clean them before enabling admission: #{sample}"
  rescue SessionRuntimeInventory::Unavailable => e
    # An inventory we could not read is not an empty one.
    raise Refused, e.message
  end
end
