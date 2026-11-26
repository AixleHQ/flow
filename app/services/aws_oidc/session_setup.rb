# frozen_string_literal: true

module AwsOidc
  # What a workflow step's container needs to use its AWS roles
  # (docs/design/aws-oidc-integration.md §6.2, §6.3): the vending env and one
  # ~/.aws/config profile per role, whose credential_process asks the platform.
  module SessionSetup
    HELPER = "/usr/local/bin/aixle-aws-creds"

    module_function

    def roles(session)
      return [] if session.project.nil?

      ids = SessionConfigResolver.new(session).resolve_aws_oidc_role_ids
      return [] if ids.empty?

      AwsOidcRole.for_project(session.project).where(id: ids).includes(:integration).order(:name)
                 .select { |role| role.integration.active? }
    end

    # Same variables and key as the Bedrock helper: one helper serves both, and a session
    # with both gets the same values from either source.
    def container_env(session, url:)
      return {} if url.blank? || roles(session).empty?

      { "AIXLE_CLOUD_CREDENTIALS_URL" => url, "AIXLE_CLOUD_KEY" => CloudAuth::SessionKey.generate(session) }
    end

    # `default:` also writes the role as [default], for a step with one role and nothing
    # else claiming the default credential chain.
    def config_file(roles, default:)
      return nil if roles.empty?

      sections = roles.map { |role| section("profile #{role.name}", role) }
      sections.unshift(section("default", roles.first)) if default && roles.one?
      "#{sections.join("\n\n")}\n"
    end

    def section(header, role)
      [ "[#{header}]", "credential_process = #{HELPER} --role #{role.name}", "region = #{role.region}" ].join("\n")
    end
  end
end
