# frozen_string_literal: true

module MailerHelper
  # Apple Mail, Outlook for Mac, Thunderbird and Samsung Mail load Inter; Gmail,
  # Yahoo and Outlook.com never fetch web fonts and fall through to the system face.
  FONT_SANS = "Inter,-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif".html_safe

  def email_font = FONT_SANS

  # A bare address in the body gets auto-linked by the email client in its default
  # blue, so render it as an explicit link carrying the layout's text colour.
  def email_link(address)
    mail_to address, address, style: "color:#d1cfcd; font-weight:600; text-decoration:none;"
  end
end
