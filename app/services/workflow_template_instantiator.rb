# frozen_string_literal: true

class WorkflowTemplateInstantiator
  class Error < StandardError; end

  def initialize(project:, version:, user:)
    @project = project
    @version = version
    @user = user
  end

  def instantiate!(set_project_origin: false, name: nil)
    validate!

    ActiveRecord::Base.transaction do
      workflow = WorkflowDuplicator.new(
        @version.workflow,
        target_scope: @project,
        name: name.presence || @version.workflow_template.name
      ).duplicate!

      @project.update!(workflow_template_version: @version) if set_project_origin
      workflow
    end
  end

  private

  def validate!
    template = @version.workflow_template
    raise Error, "Template not found" unless template
    raise Error, "Template not accessible" unless template.company_id == @project.company_id
    raise Error, "Template not visible" unless WorkflowTemplate.visible_to(@user, @project.company).exists?(id: template.id)
    raise Error, "Project not accessible" unless @project.accessible_by?(@user)
  end
end
