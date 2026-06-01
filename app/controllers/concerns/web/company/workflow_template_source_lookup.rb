# frozen_string_literal: true

module Web
  module Company
    module WorkflowTemplateSourceLookup
      private

      def published_templates_for_workflows(workflows)
        return {} if workflows.blank?

        workflow_ids = workflows.map(&:id)
        result = template_meta_by_source_workflow_id(workflow_ids)

        workflows.each do |workflow|
          next if result.key?(workflow.id)

          template = manageable_workflow_templates.find do |candidate|
            workflow_matches_template_name?(workflow.name, candidate.name)
          end
          next unless template

          result[workflow.id] = template_meta(template)
        end

        result
      end

      def workflow_matches_template_name?(workflow_name, template_name)
        return true if workflow_name == template_name

        workflow_name.match?(/\A#{Regexp.escape(template_name)} \(\d+\)\z/)
      end

      def template_meta_by_source_workflow_id(workflow_ids)
        WorkflowTemplateVersion
          .joins(:workflow_template)
          .where(source_workflow_id: workflow_ids)
          .each_with_object({}) do |version, result|
            template = version.workflow_template
            next unless can_manage_workflow_template?(template)

            result[version.source_workflow_id] = template_meta(template)
          end
      end

      def manageable_workflow_templates
        scope = WorkflowTemplate.active.where(company_id: current_company.id)
        return scope if current_user.admin?

        scope.where(owner_id: current_user.id)
      end

      def can_manage_workflow_template?(template)
        current_user.admin? || template.owner_id == current_user.id
      end

      def template_meta(template)
        {
          template_id: template.id,
          template_name: template.name,
          description: template.description,
          use_case: template.use_case,
          visibility: template.visibility
        }
      end
    end
  end
end
