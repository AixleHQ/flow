# frozen_string_literal: true

# How long a credential that just stopped on its provider's quota is held out of
# team picks (docs/design/project-teams.md, "Quota exhaustion"): until the reset
# of the usage window that is full, else the date the CLI printed, else an hour.
module QuotaHold
  FALLBACK = 1.hour
  # A window this full is the one the CLI stopped on.
  FULL_UTILIZATION = 99.0
  # Claude Code: "You will regain access on Nov 14 at 9am (UTC)."
  REGAIN_ACCESS = /regain access on\s+(.+?)(?:\.\s|\.?\s*\z|\n)/i

  module_function

  # @return [Time] the time the hold ends
  def apply!(credential, message, usage: Agents::SubscriptionUsageService.new(force: true))
    until_at = from_usage(credential, usage) || from_message(message) || FALLBACK.from_now
    # update_column: updated_at keys the usage cache, and a hold is not a new login.
    credential.update_column(:quota_exhausted_until, until_at)
    until_at
  end

  def from_usage(credential, usage)
    windows = Array(usage.usage_for(credential)&.dig(:windows))
    windows.select { |window| window[:utilization].to_f >= FULL_UTILIZATION }
           .filter_map { |window| parse(window[:resets_at]) }
           .select(&:future?).max
  end

  def from_message(message)
    match = REGAIN_ACCESS.match(message.to_s)
    time = match && parse(match[1].sub(/\s+at\s+/i, " ").delete("()"))
    time&.future? ? time : nil
  end

  def parse(value)
    return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
