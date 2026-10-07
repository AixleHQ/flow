# frozen_string_literal: true

module Agents
  # Hands a credential's current grant to every live container holding it, after a write
  # replaced one of its refresh tokens (AgentCredential#fan_out_rotation). The session the
  # write was made for already has it.
  class CredentialFanOutJob < ApplicationJob
    queue_as :default

    def perform(credential_id, origin_session_id = nil)
      credential = AgentCredential.find_by(id: credential_id)
      return unless credential&.active?

      holders = credential.live_holder_sessions(excluding_session_id: origin_session_id)
                          .where.not(container_id: [ nil, "" ]).to_a
      return if holders.empty?

      result = CredentialDelivery.new.deliver(credential, sessions: holders)
      Rails.logger.info("[CredentialFanOut] credential=#{credential.id} delivered=#{result.delivered} failed=#{result.failed}")
    end
  end
end
