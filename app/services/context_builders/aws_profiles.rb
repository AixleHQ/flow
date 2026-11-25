# frozen_string_literal: true

module ContextBuilders
  # Tells a workflow step which AWS profiles it has (docs/design/aws-oidc-integration.md §6.3).
  # Profiles, not keys: each one resolves short-lived credentials on demand, so nothing
  # secret appears here.
  class AwsProfiles < Base
    def applicable?
      roles.any?
    end

    def build
      [ section(tag: "aws-profiles", priority: :important, content: content) ]
    end

    private

    def roles
      @roles ||= AwsOidc::SessionSetup.roles(session)
    end

    def content
      lines = [ "## AWS access" ]
      lines << ""
      lines << "This step can call AWS through the profiles below. Credentials are fetched on " \
               "demand and last at most an hour; there is no access key to look for or to ask for."
      lines << ""
      lines << "| Profile | Role | Account | Region |"
      lines << "|---|---|---|---|"
      roles.each do |role|
        lines << "| `#{role.name}` | `#{role.role_arn}` | #{role.account_id} | #{role.region} |"
      end
      lines << ""
      lines << "Name the profile on every call: `aws --profile #{roles.first.name} …`, " \
               "`AWS_PROFILE=#{roles.first.name}` for an SDK or a script, and `AWS_PROFILE` in the env " \
               "of an MCP server that calls AWS. Use only what the task needs: everything this role " \
               "can read may end up in what you write back."
      lines.join("\n")
    end
  end
end
