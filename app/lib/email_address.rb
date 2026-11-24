# frozen_string_literal: true

module EmailAddress
  # URI::MailTo::EMAIL_REGEXP with the trailing `*` made `+`: the domain must have a dot.
  # The stdlib one takes `name@2005`, which SES refuses (554 Invalid domain name).
  FORMAT = /\A[a-zA-Z0-9.!\#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+\z/
end
