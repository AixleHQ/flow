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

  # The referenced runner, only when it belongs to this record's tenant
  # (TenantScope's Runner rule); otherwise nil. What the "Runs on" badge reads: a
  # stale or bypassed runner_id that names another project's or company's runner
  # serializes no name or type. The check runs on the preloaded row, from the
  # record's own tenant columns, so a list that includes `:runner` adds no query.
  # `runner` is read even for a hosted row (nil, no query), so a list's
  # `includes(:runner)` counts as used.
  def owned_runner
    return if runner.nil?

    company_id, project_id = runner_tenant_ids
    runner if TenantScope.owns_runner?(runner, company_id: company_id, project_id: project_id)
  end

  private

  # [company_id, project_id] of the tenant a runner must belong to: the project
  # of #runner_project, or none, which owns no runner. A model overrides it to
  # read its own columns instead of loading the project.
  def runner_tenant_ids
    project = runner_project
    [ project&.company_id, project&.id ]
  end
end
