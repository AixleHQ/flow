class ApplicationMailer < ActionMailer::Base
  include Rails.application.routes.url_helpers
  default from: "noreply@#{Settings.domain}"
  layout "mailer"

  # The shared mailer layout renders the Aixle wordmark. Email clients strip
  # JavaScript (so an onerror fallback never fires) and Gmail refuses to render
  # data: URIs, so the logo ships as a CID inline attachment referenced from the
  # layout via attachments["flow-logo.png"].url. The layout tolerates a missing
  # attachment, so a logo problem never blocks mail delivery.
  LOGO_PATH = Rails.root.join("app/assets/images/mailer/flow-logo.png").freeze
  LOGO_DATA =
    begin
      File.binread(LOGO_PATH).freeze
    rescue SystemCallError => e
      Rails.logger.warn("[ApplicationMailer] logo unavailable: #{e.message}")
      nil
    end

  before_action :attach_logo

  private

  def attach_logo
    return if LOGO_DATA.nil?

    attachments.inline["flow-logo.png"] = {
      data: LOGO_DATA,
      mime_type: "image/png"
    }
  end
end
