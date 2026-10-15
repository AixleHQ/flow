# frozen_string_literal: true

module AzureDevops
  # What the connected identity can ACTUALLY do in each project, asked of Azure
  # through its permission evaluation rather than inferred from which group the
  # identity sits in. Contributors, a custom group, a deny somewhere up the
  # hierarchy and a group nested inside another all end up as the same question:
  # does Azure allow this action on this resource for the caller.
  #
  # Bit values are never written down here. Each security namespace is asked for
  # its own action list and the actions are looked up by name, so a number
  # remembered wrongly cannot silently grant or deny anything.
  #
  # An answer that cannot be obtained is `unknown`, not `missing`: only an
  # explicit "no" from Azure blocks a connection. The check was written against
  # Microsoft's documentation and has not been run against a live organization.
  class PermissionCheck
    GIT_NAMESPACE = "2e9eb7ed-3c0a-47d4-87c1-0ffdd275fd87"
    BUILD_NAMESPACE = "33344d9c-fc72-4d6f-aba5-fa317101a7e9"
    CLASSIFICATION_NAMESPACE = "83e28ad4-2d72-4ceb-97b0-c7726d5502c3"
    SERVICE_HOOKS_NAMESPACE = ServiceHookGrant::NAMESPACE_ID

    Check = Struct.new(:key, :group, :label, :namespace, :action, :required, :token, keyword_init: true)
    Item = Struct.new(:key, :group, :label, :required, :status, keyword_init: true)

    # `required`: without it the connection cannot do its core job (clone, push
    # and open pull requests). The rest are reported but do not stop a
    # connection: Boards and Pipelines only matter to a project that uses them,
    # and Service Hooks only buy instant CI gates and Boards triggers.
    CHECKS = [
      Check.new(key: "repos_read", group: "Repos", label: "Read", required: true,
                namespace: GIT_NAMESPACE, action: "GenericRead", token: :repository),
      Check.new(key: "repos_contribute", group: "Repos", label: "Contribute", required: true,
                namespace: GIT_NAMESPACE, action: "GenericContribute", token: :repository),
      Check.new(key: "repos_create_branch", group: "Repos", label: "Create branch", required: true,
                namespace: GIT_NAMESPACE, action: "CreateBranch", token: :repository),
      Check.new(key: "repos_pull_requests", group: "Repos", label: "Contribute to pull requests", required: true,
                namespace: GIT_NAMESPACE, action: "PullRequestContribute", token: :repository),
      Check.new(key: "boards_view", group: "Boards", label: "View work items in this node", required: false,
                namespace: CLASSIFICATION_NAMESPACE, action: "WORK_ITEM_READ", token: :area_path),
      Check.new(key: "boards_edit", group: "Boards", label: "Edit work items in this node", required: false,
                namespace: CLASSIFICATION_NAMESPACE, action: "WORK_ITEM_WRITE", token: :area_path),
      Check.new(key: "builds_view", group: "Pipelines", label: "View builds", required: false,
                namespace: BUILD_NAMESPACE, action: "ViewBuilds", token: :project),
      Check.new(key: "hooks_view", group: "Service Hooks", label: "View subscriptions", required: false,
                namespace: SERVICE_HOOKS_NAMESPACE, action: "ViewSubscriptions", token: :service_hooks),
      Check.new(key: "hooks_edit", group: "Service Hooks", label: "Edit subscriptions", required: false,
                namespace: SERVICE_HOOKS_NAMESPACE, action: "EditSubscriptions", token: :service_hooks)
    ].freeze

    ProjectReport = Struct.new(:project_id, :name, :items, keyword_init: true) do
      def missing = items.select { |item| item.status == :missing }
      def missing_required = missing.select(&:required)
    end

    Report = Struct.new(:projects, keyword_init: true) do
      # Blocking is only ever an explicit refusal of something required.
      def ok? = projects.all? { |project| project.missing_required.empty? }

      def missing_required
        projects.flat_map { |project| project.missing_required.map { |item| [ project, item ] } }
      end

      def to_h
        {
          ok: ok?,
          projects: projects.map do |project|
            { id: project.project_id, name: project.name,
              items: project.items.map { |i| i.to_h.slice(:key, :group, :label, :required, :status) } }
          end
        }
      end

      def summary
        pairs = missing_required
        return nil if pairs.empty?

        pairs.group_by { |project, _| project.name.presence || project.project_id }.map do |name, rows|
          "#{name}: #{rows.map { |_, item| "#{item.group} → #{item.label}" }.join(', ')}"
        end.join("; ")
      end
    end

    def initialize(client:, logger: Rails.logger)
      @client = client
      @logger = logger
      @namespace_actions = {}
    end

    # `projects` is an array of { id:, name: }.
    def call(projects)
      Report.new(projects: projects.map { |project| check_project(project) })
    end

    private

    def check_project(project)
      project_id = project[:id].to_s
      tokens = {
        repository: "repoV2/#{project_id}",
        project: project_id,
        service_hooks: ServiceHookGrant.token_for(project_id),
        area_path: area_path_token(project_id)
      }

      items = CHECKS.map do |check|
        Item.new(key: check.key, group: check.group, label: check.label, required: check.required,
                 status: evaluate(check, tokens[check.token]))
      end
      ProjectReport.new(project_id: project_id, name: project[:name], items: items)
    end

    def evaluate(check, token)
      return :unknown if token.blank?

      bit = action_bit(check.namespace, check.action)
      return :unknown if bit.nil?

      answer = @client.get("_apis", "permissions", check.namespace, bit, params: { tokens: token })
      value = Array(answer["value"])
      return :unknown unless value.size == 1 && [ true, false ].include?(value.first)

      value.first ? :granted : :missing
    rescue Error => e
      @logger.info("[AzureDevops::PermissionCheck] #{check.key} could not be evaluated: #{e.code}")
      :unknown
    end

    # The bit of a named action, from the namespace's own definition.
    def action_bit(namespace, action)
      actions = (@namespace_actions[namespace] ||= load_actions(namespace))
      actions[action]
    end

    def load_actions(namespace)
      payload = @client.get("_apis", "securitynamespaces", namespace)
      definition = Array(payload["value"]).first || {}
      Array(definition["actions"]).to_h { |entry| [ entry["name"], entry["bit"] ] }
    rescue Error => e
      @logger.info("[AzureDevops::PermissionCheck] namespace #{namespace} unavailable: #{e.code}")
      {}
    end

    # Work item permissions hang off the root of the project's area path tree.
    def area_path_token(project_id)
      node = @client.get("_apis", "wit", "classificationnodes", "areas",
                         project: project_id, params: { "$depth" => 0 }, family: :wit)
      identifier = node["identifier"].presence
      identifier ? "vstfs:///Classification/Node/#{identifier}" : nil
    rescue Error
      nil
    end
  end
end
