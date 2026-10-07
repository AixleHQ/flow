# frozen_string_literal: true

module Agents
  # Hands a freshly-rotated token to the containers already running on the old one.
  #
  # Launching a session copies the credential into the container, so one grant ends up with
  # as many holders as there are live containers, plus our own row. Whoever refreshes first
  # rotates the family and every other holder is carrying something the vendor now rejects.
  # Until now we resolved that by not refreshing at all while a container held the tokens —
  # which is why a credential pinned by an idle session died of old age instead
  # (docs/design/agent-credential-lifecycle.md §3.1).
  #
  # Refreshing and then delivering is the other resolution: the rotation happens once, here,
  # and the holders are handed the result. Only the token is written — never the
  # rendered configuration, which a delivery has no workflow_config to reproduce.
  #
  # Whether a CLI already running takes the new file: Claude Code 2.1.281 re-reads its
  # credentials file on every 401 and again inside its refresh lock before spending a refresh
  # token (read from the binary, not yet observed on a live container), so a holder adopts a
  # delivered token the next time its own one is refused or due.
  class CredentialDelivery
    Result = Struct.new(:delivered, :failed, :sessions, keyword_init: true)

    def initialize(runtime: nil)
      @runtime = runtime
    end

    # @param credential [AgentCredential] carrying the tokens to hand out
    # @param sessions [Enumerable<TerminalSession>] the holders to write to
    # @return [Result] how many containers took it, how many could not be written, and which took it
    def deliver(credential, sessions:)
      adapter = credential.adapter
      credentials = credential.config_data
      return Result.new(delivered: 0, failed: 0, sessions: []) unless adapter.credential_deliverable?(credentials)

      took = []
      failed = 0

      sessions.each do |session|
        next if session.container_id.blank?

        if write(session, adapter, credentials)
          took << session
          Sessions::AuthPause.new(session, runtime: container_runtime).resume!
        else
          failed += 1
        end
      end

      Result.new(delivered: took.size, failed: failed, sessions: took)
    end

    private

    attr_reader :runtime

    # A delivery that fails is logged and counted, never raised: the sweep that called it
    # has already rotated the token and persisted it, and the next launch reads the stored
    # copy regardless. A container we could not write to is one that was going to die on
    # its stale token anyway.
    def write(session, adapter, credentials)
      raise "the container did not take it" unless adapter.deliver_credential(container_runtime, session.container_id, credentials)

      Rails.logger.info("[CredentialDelivery] session=#{session.id} container=#{session.container_id} " \
                        "took a refreshed #{session.agent_type} token")
      true
    rescue StandardError => e
      Rails.logger.warn("[CredentialDelivery] session=#{session.id} container=#{session.container_id} " \
                        "could not take the refreshed token: #{e.class}: #{e.message}")
      false
    end

    def container_runtime
      @container_runtime ||= runtime || ContainerRuntime.build
    end
  end
end
