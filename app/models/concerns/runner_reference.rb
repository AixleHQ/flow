# frozen_string_literal: true

# A nullable reference to the Runner a workflow declares, a run resolved to or
# a session used (docs/design/agent-runtimes/DESIGN.md §2.4). Null means hosted.
#
# The write checks the tenant rule only (TenantScope): the runner is a company
# runner of the record's project's company, or one of that project's own,
# deleted or not. A record with no project, such as a System workflow, can only
# be hosted. A reference is never
# cleared when its runner goes away (§3.4), so a version restore or a frozen run
# keeps naming it, and the launch fails with that name. What a person may pick
# (the flag, a live runner) is Runners::Selection, at the endpoints that take
# a pick.
module RunnerReference
  extend ActiveSupport::Concern

  included do
    belongs_to :runner, optional: true

    validates :runner_id, tenant_ids: { model: Runner, project: :runner_project, error_on: :runner },
                          if: -> { runner_id.present? && will_save_change_to_runner_id? }
  end
end
