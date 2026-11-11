# frozen_string_literal: true

require "test_helper"

module ProjectTeams
  class QuotaEventTest < ActiveSupport::TestCase
    setup do
      @owner = create(:user, :with_company)
      @company = @owner.companies.first
      create(:agent_credential, user: @owner, company: @company)
      @project = create(:project, company: @company, owner: @owner)
      @handover = create(:workflow, scope: @project, name: "Hand over")
      create(:step, :non_interactive, workflow: @handover)
      @listener = create(:trigger_binding, project: @project, workflow: @handover, created_by: @owner,
                                           event_type: QuotaEvent::EVENT_TYPE)
      TemporalWorkflowRegistry.stubs(:start_workflow_execution).returns(ok: true)
    end

    def stopped_run
      create(:workflow_run, :failed, project: @project, workflow: create(:workflow, scope: @project), user: @owner)
    end

    test "an event trigger listening for quota stops starts its workflow" do
      run = stopped_run

      QuotaEvent.publish(run, AgentCredential.find_by!(user: @owner))

      dispatch = TriggerDispatch.find_by!(trigger_binding: @listener)
      assert_equal @handover, dispatch.workflow_run.workflow
      assert_equal run.id, dispatch.trigger_event.data["workflow_run_id"]
    end

    test "a run that this event started does not raise it again" do
      QuotaEvent.publish(stopped_run, nil)
      handover_run = TriggerDispatch.find_by!(trigger_binding: @listener).workflow_run

      assert_no_difference -> { TriggerEvent.count } do
        QuotaEvent.publish(handover_run, nil)
      end
    end

    test "a webhook cannot pass itself off as an event about runs" do
      TriggerEngine.publish(event_type: QuotaEvent::EVENT_TYPE, source: "webhook", project: @project,
                            data: {}, dedup_key: "forged")

      assert_equal 0, TriggerDispatch.count
    end
  end
end
