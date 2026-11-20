# frozen_string_literal: true

# A suspended session can be restored for 30 days and is finished after that
# (Sessions::Suspension). Its owner is told when it is suspended, and again three days
# before the window closes.
class SessionMailer < ApplicationMailer
  def suspended(session_id)
    load_session(session_id)
    return if @session.nil?

    mail(to: @session.user.email, subject: "Your session ##{@session.id} was suspended — restore it by #{@expires_on}")
  end

  def restore_expiring(session_id)
    load_session(session_id)
    return if @session.nil? || !@session.suspended?

    mail(to: @session.user.email, subject: "Session ##{@session.id} can be restored until #{@expires_on}")
  end

  private

  def load_session(session_id)
    @session = TerminalSession.find_by(id: session_id)
    return if @session&.user.nil?

    @reason = @session.session_checkpoint&.manifest.to_h["reason"]
    @expires_on = @session.restore_expires_at&.utc&.strftime("%B %-d, %Y")
    @session_url = session_url_for(@session)
  end

  def session_url_for(session)
    options = { host: Settings.domain, protocol: Settings.protocol }
    return company_project_session_url(session.project_id, session.id, **options) if session.project_id

    company_session_url(session.id, **options)
  end
end
