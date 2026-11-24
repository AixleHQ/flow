# frozen_string_literal: true

# URI::MailTo::EMAIL_REGEXP accepts `name@2005`, which SES refuses at DATA
# (554 Invalid domain name), so the mail is lost. Require a dotted domain.
module EmailAddress
  DOTTED_DOMAIN = /@[^@]+\.[^@]+\z/
end
