# frozen_string_literal: true

require "test_helper"

class InternalTools::BaseTest < ActiveSupport::TestCase
  setup do
    @session = Object.new
    @session.define_singleton_method(:project) { nil }
    @session.define_singleton_method(:step_run) { nil }
  end

  test "success returns exit_code 0 with stdout" do
    handler = InternalTools::Base.new(params: {}, session: @session)
    result = handler.send(:success, "hello")

    assert_equal 0, result[:exit_code]
    assert_equal "hello", result[:stdout]
    assert_equal "", result[:stderr]
  end

  test "error returns exit_code 1 with stderr" do
    handler = InternalTools::Base.new(params: {}, session: @session)
    result = handler.send(:error, "something broke")

    assert_equal 1, result[:exit_code]
    assert_equal "", result[:stdout]
    assert_equal "something broke", result[:stderr]
  end

  test "execute raises NotImplementedError" do
    handler = InternalTools::Base.new(params: {}, session: @session)
    assert_raises(NotImplementedError) { handler.execute }
  end

  test "require_workflow_context! raises when no step_run" do
    handler = InternalTools::Base.new(params: {}, session: @session)
    assert_raises(InternalTools::WorkflowContextError) { handler.send(:require_workflow_context!) }
  end

  test "require_workflow_context! passes when step_run present" do
    step_run = Object.new
    @session.define_singleton_method(:step_run) { step_run }

    handler = InternalTools::Base.new(params: {}, session: @session)
    assert_nothing_raised { handler.send(:require_workflow_context!) }
  end

  test "params are accessible with indifferent access" do
    handler = InternalTools::Base.new(params: { "foo" => "bar" }, session: @session)
    assert_equal "bar", handler.params[:foo]
    assert_equal "bar", handler.params["foo"]
  end

  test "project delegates to session" do
    project = Object.new
    @session.define_singleton_method(:project) { project }

    handler = InternalTools::Base.new(params: {}, session: @session)
    assert_equal project, handler.send(:project)
  end

  test "workflow_run chains through step_run" do
    workflow_run = Object.new
    step_run = Object.new
    step_run.define_singleton_method(:workflow_run) { workflow_run }
    @session.define_singleton_method(:step_run) { step_run }

    handler = InternalTools::Base.new(params: {}, session: @session)
    assert_equal workflow_run, handler.send(:workflow_run)
  end
end
