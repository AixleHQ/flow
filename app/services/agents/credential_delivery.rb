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
  # What this cannot promise: that a CLI already running re-reads the file. Claude Code is
  # documented to reload settings live, its credential store is not, and the probe that
  # would settle it has not been run. So callers deliver to sessions that are parked, not
  # mid-turn — for those the old token is dead either way, and the file is what the CLI
  # reads when it wakes up.
  class CredentialDelivery
    Result = Struct.new(:delivered, :failed, keyword_init: true)

    def initialize(runtime: nil)
      @runtime = runtime
    end

    # @param credential [AgentCredential] carrying the tokens to hand out
    # @param sessions [Enumerable<TerminalSession>] the holders to write to
    # @return [Result] how many containers took it, and how many could not be written
    def deliver(credential, sessions:)
      adapter = credential.adapter
      credentials = credential.config_data
      return Result.new(delivered: 0, failed: 0) unless adapter.credential_deliverable?(credentials)

      delivered = 0
      failed = 0

      sessions.each do |session|
        next if session.container_id.blank?

        if write(session, adapter, credentials)
          delivered += 1
        else
          failed += 1
        end
      end

      Result.new(delivered: delivered, failed: failed)
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
