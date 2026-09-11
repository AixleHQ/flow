# frozen_string_literal: true

module InternalTools
  module Concerns
    # Target resolution and authorization for every Azure DevOps tool call.
    #
    # `requires_integration :azure_devops` only answers "is some Azure
    # connection present in this project" — it is an availability predicate, and
    # MCP's readOnlyHint/destructiveHint annotations are display hints the spec
    # itself calls untrusted. Neither decides whether THIS call may touch THIS
    # repository or work item. That is decided here, in the order the design
    # sets out:
    #
    #   1. an authorized, active project session
    #   2. repository tools: the local id must be in session.repositories
    #   3. work-item tools: an EXPLICIT integration_id — never "the first Azure
    #      connection in the project", which would silently pick a target
    #   4. the connection, its installation binding and its capability profile
    #   5. every fetched entity re-checked against that scope before it is
    #      returned or mutated
    module AzureDevopsContext
      extend ActiveSupport::Concern

      private

      # Repository-scoped tools derive the integration FROM the repository, so a
      # caller cannot pair someone else's repository with a connection they do
      # have access to.
      def resolve_repository!
        id = params[:repository_id]
        raise AzureDevops::ValidationFailed, "repository_id is required" if id.blank?

        repository = session&.repositories&.find_by(id: id)
        raise AzureDevops::NotAuthorized, "Repository #{id} is not attached to this session" if repository.nil?
        unless repository.azure_devops?
          raise AzureDevops::ValidationFailed, "Repository #{id} is not an Azure DevOps repository"
        end

        integration = repository.integration
        verify_project_ownership!(integration)
        [ repository, integration ]
      end

      # Work items belong to an Azure project, not to a repository, so there is
      # nothing to derive the connection from. Requiring the id is the point:
      # defaulting would make "which project did the agent just file a bug in"
      # depend on row order.
      def resolve_integration!
        id = params[:integration_id]
        if id.blank?
          raise AzureDevops::ValidationFailed,
                "integration_id is required — call azure_devops_list_connections to see the eligible connections"
        end

        integration = Integration.find_by(id: id)
        raise AzureDevops::NotAuthorized, "No such Azure DevOps connection" if integration.nil? || !integration.azure_devops?

        verify_project_ownership!(integration)
        integration
      end

      # Tool attachment authorizes project-scoped Azure usage. A connection from
      # another project — or another company — is out of reach even when the
      # caller knows its id.
      def verify_project_ownership!(integration)
        return if integration.project_id == session&.project_id &&
                  integration.company_id == session&.project&.company_id

        raise AzureDevops::NotAuthorized, "That Azure DevOps connection belongs to another project"
      end

      def eligible_integrations
        return Integration.none if project.nil?

        Integration.where(project_id: project.id, provider: "azure_devops").active
      end

      # Mutations run through the operations ledger so a retry is answerable.
      # Three outcomes, and the third is the one that matters: a dispatched
      # request whose answer never arrived is `unknown`, not failed, because
      # reissuing it is what produces duplicate pull requests and comments.
      def with_operation(integration, operation, payload)
        key = params[:operation_key].presence
        raise AzureDevops::ValidationFailed, "operation_key is required for #{operation}" if key.blank?

        record, state = AzureDevopsOperation.claim!(
          integration: integration, key: key, operation: operation,
          payload: payload, session: session, user: session&.user
        )

        return replayed_result(record) if state == :replayed

        begin
          result = yield
          record.succeed!(result, target_kind: operation, target_id: result[:id] || result["id"])
          success(result.merge(operation_key: key).to_json)
        rescue AzureDevops::OutcomeUnknown => e
          record.unknown!
          error({
            error: "outcome_unknown",
            message: "#{e.message}. The request may have been applied. Read the current state before retrying — " \
                     "reissuing this call can create a duplicate.",
            operation_key: key
          }.to_json)
        rescue AzureDevops::Error => e
          record.fail!(e.code)
          error(e.to_h.merge(operation_key: key).to_json)
        end
      end

      def replayed_result(record)
        case record.state.to_s
        when "succeeded"
          success(record.result.merge("operation_key" => record.operation_key, "replayed" => true).to_json)
        when "unknown"
          error({ error: "outcome_unknown", operation_key: record.operation_key,
                  message: "An earlier call with this operation_key was dispatched and never confirmed. " \
                           "Read the current state instead of retrying." }.to_json)
        when "failed"
          error({ error: record.error_code.presence || "failed", operation_key: record.operation_key,
                  replayed: true }.to_json)
        else
          error({ error: "operation_in_flight", operation_key: record.operation_key,
                  message: "Another call with this operation_key is still running." }.to_json)
        end
      end

      # One place that turns an adapter error into a tool result, so every Azure
      # tool reports the same stable codes (§10) instead of a provider message.
      def azure_guard
        yield
      rescue AzureDevopsOperation::Conflict => e
        error({ error: "conflict", message: e.message }.to_json)
      rescue AzureDevops::Error => e
        error(e.to_h.to_json)
      end
    end
  end
end
