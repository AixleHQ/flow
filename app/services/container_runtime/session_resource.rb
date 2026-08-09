# frozen_string_literal: true

module ContainerRuntime
  # One reapable object a runtime created on behalf of an agent session.
  #
  # `route_token` is the reconciliation key — it is what ties the object back to
  # the `TerminalSession` that owns it (`terminal_sessions.route_token`, uniquely
  # indexed). A resource whose `route_token` is blank has no provable owner and
  # must therefore never be a garbage-collection candidate.
  #
  # `created_at` is the object's own creation time as the runtime reports it
  # (Kubernetes `metadata.creationTimestamp`, Docker's `Created`), not the
  # session's — it is what the sweeper's minimum-age guard is measured against,
  # so an object that came into existence seconds ago cannot be reaped no matter
  # what the database says.
  SessionResource = Struct.new(:kind, :name, :namespace, :route_token, :created_at, keyword_init: true) do
    def to_s
      namespace.present? ? "#{kind} #{namespace}/#{name}" : "#{kind} #{name}"
    end
  end
end
