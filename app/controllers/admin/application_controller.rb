# frozen_string_literal: true

module Admin
  class ApplicationController < Administrate::ApplicationController
    include AuthConcern

    helper_method :current_user, :true_user, :impersonated?

    before_action :authenticate_admin!

    # Administrate renders HTML only, so a request for any other format has no
    # template and used to end in a 500.
    rescue_from ActionView::MissingTemplate do |error|
      raise error if request.format.html?

      head :not_acceptable
    end

    # Re-add associations skipped via {SkipAdministrateCollectionIncludes} on dashboards — they are
    # still needed on standalone index tables, but redundant on nested Administrate collections.
    # Also preloads what virtual index columns read, so they do not query per row.
    INDEX_COLLECTION_INCLUDES_EXTRAS = {
      "Company" => [ :session_concurrency_limit_row ],
      "Step" => [ :workflow ],
      "TaskComment" => [ :board_task ],
      "BoardColumn" => [ :board ],
      "ToolFile" => [ :tool ],
      "BoardTask" => [ :board, :board_column ],
      "StepRun" => [ :workflow_run ],
      "SubStepRun" => [ :step_run ],
      "Repository" => [ :integration ],
      "SessionLog" => [ :terminal_session ],
      "SubStep" => [ :step ],
      "TaskAsset" => [ :board_task ],
      "WorkflowRunAsset" => [ :workflow_run ],
      "WorkflowRun" => [ :workflow, :project, :user ],
      "ColumnWorkflowBinding" => [ :workflow ]
    }.freeze

    INVITATION_FAILURES_LISTED = 5

    def records_per_page
      params[:per_page] || 20
    end

    # administrate-field-jsonb edits a jsonb column as JSON text, and a String
    # assigned to a jsonb column is stored as a JSON string rather than parsed: an
    # object became a string of itself on the first save, and every later save
    # quoted it again. The text is parsed here; a blank or `null` editor means the
    # column's default. Text that is not JSON leaves the column as it was.
    def resource_params
      permitted = super
      jsonb_attributes.each do |attribute|
        text = permitted[attribute]
        next unless text.is_a?(String)

        permitted[attribute] = parse_jsonb(attribute, text)
      rescue JSON::ParserError
        permitted.delete(attribute)
        flash[:alert] = "#{attribute.to_s.humanize} was not valid JSON and was left as it was."
      end
      permitted
    end

    def jsonb_attributes
      dashboard.class::ATTRIBUTE_TYPES.filter_map do |attribute, type|
        field = type.respond_to?(:deferred_class) ? type.deferred_class : type
        attribute if field <= Administrate::Field::JSONB
      end
    end

    def parse_jsonb(attribute, text)
      value = JSON.parse(text) if text.strip.present?
      value.nil? ? resource_class.column_defaults[attribute.to_s] : value
    end

    def apply_collection_includes(relation)
      includes = dashboard.collection_includes
      if action_name == "index"
        extras = INDEX_COLLECTION_INCLUDES_EXTRAS[resource_class.name] || []
        includes = (includes + extras).uniq
      end
      return relation if includes.empty?

      relation.includes(*includes)
    end

    private

    # The flash travels in the session cookie, which holds 4 KB: a long pasted
    # list is counted, not echoed. Who was invited shows on the invitations page.
    def invitation_flash(results)
      sent, failed = results.partition(&:sent?)
      unsent, refused = failed.partition(&:unsent?)
      messages = {}
      messages[:notice] = "Invitations sent to #{helpers.pluralize(sent.size, 'address')}." if sent.any?
      alerts = []
      alerts << "Not invited: #{list_invitation_failures(refused.map(&:message), '; ')}." if refused.any?
      if unsent.any?
        alerts << "Invited, but the email could not be sent to #{list_invitation_failures(unsent.map(&:email), ', ')}. " \
                  "Re-send it from Members below."
      end
      messages[:alert] = alerts.join(" ") if alerts.any?
      messages
    end

    def list_invitation_failures(items, separator)
      listed = items.first(INVITATION_FAILURES_LISTED)
      listed << "#{items.size - listed.size} more" if items.size > listed.size
      listed.join(separator)
    end
  end
end
