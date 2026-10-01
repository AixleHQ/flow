# frozen_string_literal: true

module Auth
  # "Link this method to my account", held in the session between the POST that
  # asks for it and the OmniAuth callback that completes it. Server-side and
  # never a URL parameter: a callback URL is something an attacker can make a
  # victim's browser open, and it must not be able to turn a sign-in into a link.
  #
  # Bound to the UserSession that asked, so a rotated or ended session voids
  # it, and single-use: the callback takes it whether or not it is honoured.
  module LinkIntent
    KEY = "identity_link_intent"
    TTL = 10.minutes

    Intent = Struct.new(:kind, :user_session_id, :expires_at, keyword_init: true) do
      def honoured_for?(user_session, provider)
        user_session&.live? &&
          user_session.id == user_session_id &&
          provider.kind.to_s == kind &&
          Time.current.to_i < expires_at.to_i
      end
    end

    module_function

    def start(session, user_session:, kind:)
      session[KEY] = { "kind" => kind.to_s, "user_session_id" => user_session.id, "expires_at" => TTL.from_now.to_i }
    end

    def take(session)
      stored = session.delete(KEY)
      return nil unless stored.is_a?(Hash)

      Intent.new(kind: stored["kind"].to_s, user_session_id: stored["user_session_id"], expires_at: stored["expires_at"])
    end

    def discard(session)
      session.delete(KEY)
    end
  end
end
