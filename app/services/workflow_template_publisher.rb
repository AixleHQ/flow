# frozen_string_literal: true

class WorkflowTemplatePublisher
  class Error < StandardError; end

  def initialize(source_workflow:, user:, company:, name:, description: nil, use_case: nil,
                 visibility: "company", workflow_template: nil, changelog: nil)
    @source = source_workflow
    @user = user
    @company = company
    @name = name
    @description = description
    @use_case = use_case
    @visibility = visibility
    @workflow_template = workflow_template
    @changelog = changelog
  end

  def publish!
    validate_source_accessible!

    ActiveRecord::Base.transaction do
      template = @workflow_template || create_template!
      update_template_metadata!(template) if @workflow_template.present?

      version = create_version!(template)
      template.update!(current_version: version)
      template
    end
  end

  private

  def validate_source_accessible!
    case @source.scope_type
    when "Company"
      raise Error, "Workflow not in company" unless @source.scope_id == @company.id
    when "Project"
      project = Project.find_by(id: @source.scope_id, company_id: @company.id)
      raise Error, "Workflow not accessible" unless project&.accessible_by?(@user)
    else
      raise Error, "Cannot publish system workflow"
    end
  end

  def create_template!
    existing = WorkflowTemplate.active.find_by(company: @company, name: @name)
    if existing
      if can_manage_template?(existing)
        raise Error, "A template named \"#{@name}\" already exists. Use Publish new version from the workflow page instead."
      end

      raise Error, "A template named \"#{@name}\" already exists in your company catalog."
    end

    WorkflowTemplate.create!(
      company: @company,
      owner: @user,
      name: @name,
      description: @description,
      use_case: @use_case,
      visibility: @visibility
    )
  end

  def can_manage_template?(template)
    @user.admin? || template.owner_id == @user.id
  end

  def update_template_metadata!(template)
    template.update!(
      name: @name,
      description: @description,
      use_case: @use_case,
      visibility: @visibility
    )
  end

  def create_version!(template)
    snapshot = WorkflowDuplicator.new(
      @source,
      target_scope: @company,
      kind: "template_snapshot",
      name: snapshot_name(template)
    ).duplicate!

    template.versions.create!(
      workflow: snapshot,
      published_by: @user,
      source_workflow: @source,
      version_number: WorkflowTemplateVersion.next_version_number(template),
      changelog: @changelog,
      published_at: Time.current
    )
  end

  def snapshot_name(template)
    "template-#{template.id}-v#{WorkflowTemplateVersion.next_version_number(template)}"
  end
end
