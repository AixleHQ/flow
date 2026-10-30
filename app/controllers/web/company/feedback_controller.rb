# frozen_string_literal: true

# POST /company/feedback — the Send feedback dialog in the user menu. Who sent it
# and from which company come from the session, never from the form.
class Web::Company::FeedbackController < Web::Company::ApplicationController
  allow_viewer_writes

  def create
    return head :not_found unless Feedback.enabled?

    submission = current_company.feedback_submissions.new(
      feedback_params.merge(user: current_user, app_version: Settings.app.version)
    )
    submission.attach(attached_files)

    if submission.save
      Feedback.deliver_later(submission)
      redirect_back fallback_location: company_projects_path, notice: "Thanks! Your feedback has been sent."
    else
      redirect_back fallback_location: company_projects_path,
                    inertia: { errors: submission.errors.to_hash(true).transform_values(&:first) }
    end
  end

  private

  def feedback_params
    params.require(:feedback).except(:attachments).permit(:kind, :message, :page_url)
  end

  # Inertia posts a list of files as feedback[attachments][0], [1], …, which
  # Rails parses as a hash keyed by position rather than as an array.
  def attached_files
    files = params[:feedback][:attachments]
    files = files.values if files.respond_to?(:values)
    Array(files).grep(ActionDispatch::Http::UploadedFile)
  end
end
