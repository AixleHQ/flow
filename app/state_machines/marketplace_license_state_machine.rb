# frozen_string_literal: true

# What AWS is allowed to tell us about a licence, and in what order.
#
# A machine rather than assignment because the events arrive over SQS, which
# neither orders messages nor delivers them once. The column decides whether an
# hour is billed, so a stale `active` landing after `ended` would charge for an
# hour nobody ran. Here it is refused instead.
#
# Every event accepts its own result as a source, so a redelivery is a no-op
# rather than an error -- except `finish`, which is the one with a side effect
# beside it (the final meter) and must happen once. `ended` is terminal: nothing
# leaves it, which is the whole point.
module MarketplaceLicenseStateMachine
  extend ActiveSupport::Concern

  included do
    include AASM
    include StateEventConcern

    aasm :subscription_state, column: :subscription_state do
      state :pending, initial: true
      state :active
      state :ending
      state :ended

      # Purchase Agreement Created - Proposer. Not from `ending` or `ended`: an
      # agreement that has closed is not reopened by a message that overtook it.
      event :confirm do
        transitions from: %i[pending active], to: :active
      end

      # Purchase Agreement Ended - Proposer. From `pending` too, because the
      # close can arrive before the creation did.
      event :close do
        transitions from: %i[pending active ending], to: :ending
      end

      # License Deprovisioned - Manufacturer, after the last usage has been
      # reported. Deliberately not from `ended`.
      event :finish do
        transitions from: %i[pending active ending], to: :ended
      end
    end
  end
end
