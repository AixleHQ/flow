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

  # An attempt whose outcome nobody can prove can simply be MADE AGAIN when the
  # phase's side effect is idempotent by construction — and the materializing
  # phases are exactly that:
  #
  # * `create_container` goes through ContainerRuntime's create_or_verify, which
  #   answers a 409 by fetching the existing object and verifying its labels and
  #   image before returning it.
  # * `start_container` creates the Service, middlewares and IngressRoute through
  #   the same path.
  #
  # `exec` is the one that cannot: it launches the agent, and doing that twice is
  # the thing AD-5 refuses replays to prevent.
  #
  # This does not weaken "unknown creation retains capacity". The reservation
  # still belongs to this admission and is never handed to anyone else; what
  # changes is that an unknown outcome is resolved by redoing a safe operation
  # rather than by waiting for an operator. Before this, every worker roll that
  # interrupted a create — spot reclaim, OOM, a rolling deploy — killed the
  # session on the retry and left the slot pinned.
  def replayable? = phase.in?(MATERIALIZING_PHASES)

  # What an unresolved operation costs the pool, said accurately. Only a create or
  # a start holds a reservation; an unaccountable `exec` is worth recording and
  # worth reading, but it takes no capacity.
  def reservation_note
    phase.in?(MATERIALIZING_PHASES) ? "reservation retained" : "no reservation is held for this phase"
  end

  scope :unresolved, -> { where(state: UNRESOLVED_STATES) }
  scope :materializing, -> { where(phase: MATERIALIZING_PHASES) }

  # The operations that must keep a reservation taken. Everything else is
  # recorded and reported, but does not cost the installation a slot.
  scope :pinning, -> { unresolved.materializing }
end
