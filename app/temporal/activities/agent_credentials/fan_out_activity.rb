# frozen_string_literal: true

module Activities
  module AgentCredentials
    # Hands a credential's current grant to every live container holding it, after a write
    # replaced one of its refresh tokens (AgentCredential#fan_out_rotation). The session the
    # write was made for already has it. An activity rather than a job: writing into a
    # container needs the container runtime, which only the worker has.
    class FanOutActivity < ::Activities::Base
      def run(input)
        credential = ::AgentCredential.find_by(id: input.credential_id)
        return { delivered: 0, failed: 0 } unless credential&.active?

        holders = credential.live_holder_sessions(excluding_session_id: input.origin_session_id)
                            .where.not(container_id: [ nil, "" ]).to_a
        return { delivered: 0, failed: 0 } if holders.empty?

        result = ::Agents::CredentialDelivery.new.deliver(credential, sessions: holders)
        log(:info, "credential #{credential.id}: delivered=#{result.delivered} failed=#{result.failed}")
        { delivered: result.delivered, failed: result.failed }
      end
    end
  end
end
