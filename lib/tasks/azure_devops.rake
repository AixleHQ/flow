# frozen_string_literal: true

# Operator onboarding for Azure DevOps.
#
# Core-release onboarding is deliberately operator-assisted rather than
# self-service. A successful app-only API call proves that THE APPLICATION can
# reach an organization; it proves nothing about whether the Aixle company asking
# owns that access, and none of the values a form could collect is that proof —
# a tenant id, an organization URL and the shared client id are all public or
# guessable, and Microsoft explicitly warns that the `tenant` returned by an
# admin-consent callback must not be used to authorize anyone.
#
# So an operator verifies the customer administrator's authority out of band and
# records it here. Everything downstream — project discovery, repository
# attachment, tool execution, git credential vending — checks the record this
# creates.
#
# Prerequisites, in order (docs/design/azure-devops-integration.md §5.2):
#   1. The deployment's multi-tenant Entra app is registered and configured
#      (AZURE_DEVOPS_CLIENT_ID plus a certificate or client secret).
#   2. The customer's Entra administrator has provisioned a service principal
#      for that client id in their own tenant.
#   3. An Azure DevOps administrator has added that principal to the
#      organization with at least a Basic access level and the project
#      permissions the connection needs.
namespace :azure_devops do
  desc "Approve an Azure DevOps organization for a company: COMPANY_ID=1 TENANT_ID=<guid> ORGANIZATION=contoso [PROJECT_IDS=guid,guid] [APPROVED_BY_ID=1] [APP=default]"
  task approve: :environment do
    company = Company.find(ENV.fetch("COMPANY_ID"))
    approver = ENV["APPROVED_BY_ID"].present? ? User.find(ENV["APPROVED_BY_ID"]) : nil

    installation = AzureDevops::InstallationService.new(company: company, approved_by: approver).provision!(
      tenant_id: ENV.fetch("TENANT_ID"),
      organization_slug: ENV.fetch("ORGANIZATION"),
      app_config_key: ENV["APP"].presence || "default",
      allowed_project_ids: ENV["PROJECT_IDS"].to_s.split(",").map(&:strip).reject(&:blank?)
    )

    puts "Installation ##{installation.id}: #{company.name} → #{installation.organization_url}"
    puts "  tenant:    #{installation.tenant_id}"
    puts "  client id: #{installation.client_id}"
    puts "  approved projects: #{installation.allowed_project_ids.presence&.join(', ') || '(none yet)'}"
    puts
    puts "Next: rake azure_devops:verify INSTALLATION_ID=#{installation.id}"
  end

  desc "Verify an installation against Azure and list the projects it can see: INSTALLATION_ID=1"
  task verify: :environment do
    installation = AzureDevopsInstallation.find(ENV.fetch("INSTALLATION_ID"))
    result = AzureDevops::InstallationService.new(company: installation.company).verify!(installation)

    puts "Installation ##{installation.id} is #{result[:status]}."
    puts
    puts "Projects the application can see in #{installation.organization_slug}:"
    result[:projects].each do |project|
      approved = installation.approved_project?(project[:id]) ? "approved" : "NOT approved"
      puts format("  %-38s  %-28s  %s", project[:id], project[:name].to_s.truncate(26), approved)
    end
    puts
    puts "Approve the ones this company may use:"
    puts "  rake azure_devops:scope INSTALLATION_ID=#{installation.id} PROJECT_IDS=<guid>,<guid>"
  rescue AzureDevops::Error => e
    # The distinction matters operationally: a credential problem is fixed in the
    # deployment's own configuration, while an access problem is fixed in the
    # customer's Azure DevOps organization.
    abort "#{e.code}: #{e.message}"
  end

  desc "Replace an installation's approved project list: INSTALLATION_ID=1 PROJECT_IDS=guid,guid"
  task scope: :environment do
    installation = AzureDevopsInstallation.find(ENV.fetch("INSTALLATION_ID"))
    ids = ENV.fetch("PROJECT_IDS").split(",").map(&:strip).reject(&:blank?)

    installation.update!(allowed_project_ids: ids)
    puts "Installation ##{installation.id} now approves: #{ids.join(', ')}"

    # Narrowing the scope must not leave a connection pointing outside it
    # pretending to work; say which ones just stopped resolving.
    orphaned = installation.integrations.reject { |i| installation.approved_project?(i.azure_project_id) }
    next if orphaned.empty?

    warn "WARNING: #{orphaned.size} existing connection(s) now fall outside the approved scope and will stop working:"
    orphaned.each { |i| warn "  integration ##{i.id} (project #{i.project_id}) → azure project #{i.azure_project_id}" }
  end

  desc "Disable an installation and clear its cached token: INSTALLATION_ID=1"
  task disable: :environment do
    installation = AzureDevopsInstallation.find(ENV.fetch("INSTALLATION_ID"))
    installation.update!(status: :inactive)
    installation.clear_token_cache!

    puts "Installation ##{installation.id} disabled; #{installation.integrations.count} connection(s) blocked."
    puts "Access tokens already handed to running sessions stay valid until Azure expires them."
  end

  desc "Create or repair Service Hook subscriptions for a project connection: INTEGRATION_ID=1 [BASE_URL=https://...]"
  task hooks: :environment do
    integration = Integration.find(ENV.fetch("INTEGRATION_ID"))
    abort "Integration ##{integration.id} is not an Azure DevOps connection" unless integration.azure_devops?

    base_url = ENV["BASE_URL"].presence || AzureDevops::AppConfig.webhook_base_url
    if base_url.blank?
      abort "No public base URL. Set AZURE_DEVOPS_WEBHOOK_BASE_URL, or pass BASE_URL= for a one-off. " \
            "Azure posts INBOUND, so an unreachable host produces subscriptions it can never deliver to."
    end

    service = AzureDevops::SubscriptionService.new(integration)
    service.ensure_all!(base_url: base_url)
    service.refresh_status!

    integration.azure_devops_subscriptions.reload.each do |subscription|
      puts format("  %-26s %-10s %s", subscription.event_type, subscription.status,
                  subscription.error_code.presence || subscription.azure_subscription_id)
    end
  end

  desc "Re-read Azure's own subscription state for a connection: INTEGRATION_ID=1"
  task hook_status: :environment do
    integration = Integration.find(ENV.fetch("INTEGRATION_ID"))
    AzureDevops::SubscriptionService.new(integration).refresh_status!

    integration.azure_devops_subscriptions.reload.each do |subscription|
      # `probation` is Azure throttling a failing subscription: it exists and
      # delivers nothing, which from here looks exactly like silence.
      note = subscription.probation? ? "  (delivering nothing while on probation)" : ""
      puts format("  %-26s %-10s last_event=%s%s", subscription.event_type, subscription.status,
                  subscription.last_event_at&.iso8601 || "never", note)
    end
  end

  desc "List the installations this deployment knows about"
  task list: :environment do
    AzureDevopsInstallation.includes(:company).order(:company_id, :organization_slug).each do |installation|
      puts format(
        "#%-4d %-24s %-20s %-9s projects=%d connections=%d",
        installation.id, installation.company.name.to_s.truncate(22),
        installation.organization_slug, installation.status,
        installation.allowed_project_ids.size, installation.integrations.count
      )
    end
  end
end
