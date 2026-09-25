# frozen_string_literal: true

# Sink for Content-Security-Policy violation reports (the fallback when no Sentry
# DSN is configured). Browsers POST here with Content-Type application/csp-report
# and no CSRF token, so this stays outside session/CSRF protection entirely.
class CspReportsController < ActionController::API
  MAX_BODY_BYTES = 16.kilobytes
  # What a violation is triaged by. Anyone can post here and it all goes to the
  # log, so nothing else is kept and every value is cut short.
  FIELDS = %w[document-uri violated-directive effective-directive blocked-uri source-file line-number disposition].freeze

  def create
    report = parsed_report
    Rails.logger.warn("[CSP Violation] #{report.to_json}") if report.present?
    head :no_content
  end

  private

  def parsed_report
    body = request.body.read(MAX_BODY_BYTES + 1)
    return nil if body.nil? || body.bytesize > MAX_BODY_BYTES

    data = JSON.parse(body)
    report = data.is_a?(Hash) ? data.fetch("csp-report", data) : nil
    return nil unless report.is_a?(Hash)

    report.slice(*FIELDS).transform_values { |value| value.to_s.truncate(300) }.presence
  rescue JSON::ParserError
    nil
  end
end
