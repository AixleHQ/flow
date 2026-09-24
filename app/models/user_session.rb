# frozen_string_literal: true

# One signed-in browser. The session cookie carries this row's id; the row is
# what makes a sign-in revocable — "sign out everywhere", an administrator, a
# suspended or deleted account — and what ends it after the idle timeout or the
# absolute one (Settings.auth).
class UserSession < ApplicationRecord
  belongs_to :user
  belongs_to :impersonator, class_name: "User", optional: true

  # last_seen_at is a timeout clock, not an access log: written at most this often.
  TOUCH_EVERY = 5.minutes
  # Ended rows are kept this long for the record, then removed at the user's next sign-in.
  KEEP_ENDED = 30.days

  scope :live, lambda {
    where(revoked_at: nil).where("last_seen_at > ?", idle_timeout.ago).where("user_sessions.created_at > ?", max_age.ago)
  }

  def self.idle_timeout = Settings.auth.session_idle_timeout_hours.to_i.hours
  def self.max_age = Settings.auth.session_max_age_hours.to_i.hours

  def self.start!(user:, request: nil, impersonator: nil)
    where(user: user).where("revoked_at < :cut OR last_seen_at < :cut", cut: KEEP_ENDED.ago).delete_all
    create!(user: user, impersonator: impersonator, last_seen_at: Time.current,
            ip_address: request&.remote_ip, user_agent: request&.user_agent.to_s.truncate(255).presence)
  end

  # Ends every live sign-in of `user` (but `except`), and drops the live
  # connections that were opened under them.
  def self.revoke_all_for!(user, except: nil)
    scope = where(user: user, revoked_at: nil)
    scope = scope.where.not(id: except.id) if except
    ended = scope.update_all(revoked_at: Time.current)
    disconnect_cables(user) if ended.positive?
    ended
  end

  def self.disconnect_cables(user)
    ActionCable.server.remote_connections.where(current_user: user).disconnect
  rescue StandardError => e
    Rails.logger.warn("[UserSession] could not drop live connections for user #{user.id}: #{e.message}")
  end

  def live?
    revoked_at.nil? && last_seen_at > self.class.idle_timeout.ago && created_at > self.class.max_age.ago
  end

  def revoke!
    update_column(:revoked_at, Time.current) if revoked_at.nil?
  end

  def touch_if_stale!
    update_column(:last_seen_at, Time.current) if last_seen_at < TOUCH_EVERY.ago
  end
end
