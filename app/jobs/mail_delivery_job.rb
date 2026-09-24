# frozen_string_literal: true

require "net/smtp"

# Every mailer delivers through this job (ApplicationMailer.delivery_job). The
# stock job does not retry, so one SMTP hiccup would lose the mail for good —
# for an invitation, the only way a person gets into the product.
class MailDeliveryJob < ActionMailer::MailDeliveryJob
  # A 4xx reply, a dropped or refused connection, a timeout. A 5xx reply
  # (Net::SMTPFatalError, Net::SMTPAuthenticationError, Net::SMTPSyntaxError)
  # will not change on retry and still fails the job.
  TRANSIENT_ERRORS = [
    Net::SMTPServerBusy, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET,
    Errno::ETIMEDOUT, Errno::EHOSTUNREACH, EOFError, SocketError, OpenSSL::SSL::SSLError
  ].freeze

  # Roughly four hours between the first attempt and the last.
  retry_on(*TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 10)
end
