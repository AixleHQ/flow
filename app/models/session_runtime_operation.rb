# frozen_string_literal: true

class SessionRuntimeOperation < ApplicationRecord
  # Nobody can prove either way whether these landed. `in_flight` is a request
  # still running, `uncertain` one whose answer will never arrive; both are
  # unresolved, and they stay separate so ordinary provisioning load never reads
  # as a fault.
  UNRESOLVED_STATES = %w[in_flight uncertain].freeze

  # Phases that can bring a workload into existence. AD-5 retains the slot for an
  # unprovable operation so a late Pod never finds its seat handed to someone
  # else — and only a create or a start can produce that Pod. `exec` runs a
  # command inside a container, so it is reached only after the create it depends
  # on, and cleanup releases nothing until that container is provably absent: a
  # late exec can then only 404. Holding a reservation for one pinned capacity
  # and protected nothing.
  MATERIALIZING_PHASES = %w[create_container start_container].freeze

  belongs_to :session_admission

  scope :unresolved, -> { where(state: UNRESOLVED_STATES) }
  scope :materializing, -> { where(phase: MATERIALIZING_PHASES) }

  # The operations that must keep a reservation taken. Everything else is
  # recorded and reported, but does not cost the installation a slot.
  scope :pinning, -> { unresolved.materializing }
end
