# frozen_string_literal: true

module Tools
  # Feature-flag policy layer over tool availability — orthogonal to the
  # capability predicate (integration presence) and AND-ed with it, never
  # conflated. Two flags per tool, actor = company:
  #
  # - Kill switch: enable "tool_kill__<name>" (globally or per company) to
  #   pull a misbehaving tool from serving immediately. Absent flag = allowed,
  #   so the flag layer adds zero ceremony to normal tools.
  # - Gradual rollout: create "tool_rollout__<name>" and the tool serves only
  #   for companies (or percentages) the flag enables. No flag = fully rolled
  #   out. Delete the flag when the rollout is done.
  module Policy
    KILL_PREFIX = "tool_kill__"
    ROLLOUT_PREFIX = "tool_rollout__"

    class << self
      def allowed?(tool_name, company)
        return false if Flipper.enabled?(:"#{KILL_PREFIX}#{tool_name}", company)

        rollout = :"#{ROLLOUT_PREFIX}#{tool_name}"
        return Flipper.enabled?(rollout, company) if Flipper.exist?(rollout)

        true
      end

      def kill!(tool_name, company: nil)
        flag = :"#{KILL_PREFIX}#{tool_name}"
        company ? Flipper.enable_actor(flag, company) : Flipper.enable(flag)
      end

      def revive!(tool_name, company: nil)
        flag = :"#{KILL_PREFIX}#{tool_name}"
        company ? Flipper.disable_actor(flag, company) : Flipper.disable(flag)
      end
    end
  end
end
