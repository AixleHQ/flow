# frozen_string_literal: true

module MailerHelper
  # A bare address in the body gets auto-linked by the email client in its default
  # blue, so render it as an explicit link carrying the layout's text colour.
  def email_link(address)
    mail_to address, address, style: "color:#d1cfcd; font-weight:600; text-decoration:none;"
  end
end
