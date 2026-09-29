# frozen_string_literal: true

# A short-lived, signed pass to one session's containers for one user.
#
# Containers are meant to be served from an origin of their own
# (TRAEFIK_HTTP_BASE on another host than DOMAIN): whatever answers on a
# container's routes is controlled by its agent, and on the app's own origin a
# page it serves would run with the viewer's standing in the app. The browser
# sends another host none of the app's cookies, so the gate in front of the
# containers (Api::V1::Internal::WsAuth) needs another way to know who is asking:
# this pass, in the container URLs the app hands out. The gate trades it on first
# use for a cookie on the sandbox host, scoped to that session's routes, so
# websockets and the IDE's own requests stay authenticated after the pass expires.
module ContainerTicket
  PURPOSE = "container-ticket"
  PARAM = "aixle_ticket"
  COOKIE = "aixle_container"
  TICKET_TTL = 10.minutes
  COOKIE_TTL = 12.hours

  module_function

  # Only when containers live on a host of their own; on the app's host the
  # session cookie already reaches the gate.
  def required?
    sandbox_host.present? && sandbox_host.casecmp?(app_host.to_s) == false
  end

  # Bound to the browser sign-in it was issued in — Current.user_session, or the
  # one a pass being exchanged carried — so ending that sign-in ends the pass and
  # the cookie it is exchanged for.
  def issue(user:, session:, ttl: TICKET_TTL, user_session_id: nil)
    user_session_id ||= Current.user_session.id if Current.user_session&.user_id == user.id
    payload = { "u" => user.id, "s" => session.id }
    payload["us"] = user_session_id if user_session_id
    verifier.generate(payload, expires_in: ttl, purpose: PURPOSE)
  end

  # The pass's payload when it is genuine, for this session, and its sign-in is live.
  def verify(token, session:)
    payload = token.present? ? verifier.verified(token.to_s, purpose: PURPOSE) : nil
    return nil unless payload.is_a?(Hash) && payload["s"] == session.id
    return nil if payload["us"] && !UserSession.live.exists?(id: payload["us"], user_id: payload["u"])

    payload
  end

  # The authenticatable user the pass was issued to, for this session only.
  def user_for(token, session:)
    payload = verify(token, session: session)
    payload && User.authenticatable.find_by(id: payload["u"])
  end

  def append(url, user:, session:)
    return url unless required? && user

    separator = url.include?("?") ? "&" : "?"
    "#{url}#{separator}#{PARAM}=#{CGI.escape(issue(user: user, session: session))}"
  end

  def sandbox_host
    URI.parse(Settings.traefik.http_base.to_s).host
  rescue URI::InvalidURIError
    nil
  end

  def app_host
    Settings.domain.to_s.split(":").first
  end

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
