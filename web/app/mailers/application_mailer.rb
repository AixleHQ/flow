class ApplicationMailer < ActionMailer::Base
  include Rails.application.routes.url_helpers
  default from: "noreply@#{Settings.domain}"
  layout "mailer"
end
