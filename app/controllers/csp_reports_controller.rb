# frozen_string_literal: true

# Sink for Content-Security-Policy violation reports (M-16, report-only mode).
# Browsers POST here with Content-Type application/csp-report and no CSRF
# token, so this stays outside session/CSRF protection entirely.
class CspReportsController < ActionController::API
  def create
    report = parsed_report
    Rails.logger.warn("[CSP Violation] #{report.to_json}") if report.present?
    head :no_content
  end

  private

  def parsed_report
    JSON.parse(request.body.read)
  rescue JSON::ParserError, TypeError
    nil
  end
end
