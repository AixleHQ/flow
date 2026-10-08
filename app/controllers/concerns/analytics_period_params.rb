# frozen_string_literal: true

# The period an analytics page was asked for (`period`, plus `from`/`to` when it
# is "custom"), resolved once per request, and the props its picker reads back.
module AnalyticsPeriodParams
  extend ActiveSupport::Concern

  private

  def analytics_window
    @analytics_window ||= AnalyticsPeriod.window(params[:period], from: params[:from], to: params[:to])
  end

  # The resolved window rather than the raw params, so a malformed custom range
  # shows the picker on the default preset the charts actually fell back to.
  def analytics_period_props
    {
      period: analytics_window.key,
      from: analytics_window.from.to_date.iso8601,
      to: analytics_window.to.to_date.iso8601
    }
  end
end
