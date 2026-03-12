# frozen_string_literal: true

# ActionCable channel for real-time terminal session updates
#
# Subscription:
#   cable.subscriptions.create({ channel: "TerminalSessionChannel", session_id: 123 })
#
# Broadcasts terminal session state changes (after_update) to subscribed clients
class TerminalSessionChannel < ApplicationCable::Channel
  def subscribed
    @terminal_session = find_terminal_session
    return reject unless @terminal_session

    # Verify ownership
    unless can_access?(@terminal_session)
      Rails.logger.warn("[TerminalSessionChannel] User #{current_user&.id} cannot access session #{params[:session_id]}")
      return reject
    end

    stream_for @terminal_session
    Rails.logger.info("[TerminalSessionChannel] Subscribed: user=#{current_user&.id}, session=#{@terminal_session.id}")

    @terminal_session.reload
    transmit_session_data(@terminal_session)
  end

  def unsubscribed
    Rails.logger.info("[TerminalSessionChannel] Unsubscribed: session=#{params[:session_id]}")
  end

  # Client can request current state
  def refresh
    return unless @terminal_session

    @terminal_session.reload
    transmit_session_data(@terminal_session)
  end

  private

  def find_terminal_session
    TerminalSession.find_by(id: params[:session_id])
  end

  def can_access?(session)
    return false unless current_user
    return true if session.user_id == current_user.id
    return true if session.project&.accessible_by?(current_user)

    false
  end

  def transmit_session_data(session)
    transmit({
      "type" => "session_update",
      "data" => serialize_session(session)
    })
  end

  def serialize_session(session)
    TerminalSessionSerializer.new(session).serializable_hash
  end

  class << self
    def broadcast_update(terminal_session)
      broadcast_to(terminal_session, {
        "type" => "terminal_session.updated",
        "data" => { id: terminal_session.id }
      })
    end
  end
end
