# frozen_string_literal: true

module Admin
  class ApplicationController < Administrate::ApplicationController
    include AuthConcern

    helper_method :current_user, :true_user, :impersonated?

    before_action :authenticate_admin!

    # Re-add associations skipped via {SkipAdministrateCollectionIncludes} on dashboards — they are
    # still needed on standalone index tables, but redundant on nested Administrate collections.
    INDEX_COLLECTION_INCLUDES_EXTRAS = {
      "User" => [ :company ],
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

    def records_per_page
      params[:per_page] || 20
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
  end
end
