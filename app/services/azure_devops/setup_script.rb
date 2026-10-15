# frozen_string_literal: true

module AzureDevops
  # The shell script a customer's Azure DevOps administrator (a Project Collection
  # Administrator) runs once, to let the customer's own Entra app work in the
  # organization. It does by hand what Onboarding does with an administrator token
  # for the shared app: add the app's service principal with a Basic license and
  # give it the permissions agents need.
  #
  # Every value placed into the script is validated to a fixed shape (an
  # organization name, GUIDs) and single-quoted. Project names are free text, so the
  # script never contains one: the administrator passes them as arguments and the
  # script looks their ids up. It talks to Azure
  # DevOps through `az rest` alone, against the same endpoints the rest of the
  # integration uses, so it needs no extension. It was not run against a live
  # organization; the connection check afterwards reports exactly what is still
  # missing.
  class SetupScript
    FLAVORS = %w[contributors custom].freeze
    PROJECT_NAMESPACE = "52d39943-cb85-4d7f-8fa8-c6baac873819"
    GUID = AzureDevopsInstallation::GUID

    COMMON = <<~'BASH'

      RESOURCE='499b84ac-1321-427f-aa17-267ca6975798'
      API="https://dev.azure.com/$ORG"

      if [ "$#" -eq 0 ]; then
        echo "Usage: $0 <Azure DevOps project name>..." >&2
        exit 1
      fi

      # The app's service principal in this directory. Set SP_OBJECT_ID yourself if your
      # account cannot read the directory.
      SP_OBJECT_ID="${SP_OBJECT_ID:-$(az ad sp show --id "$CLIENT_ID" --query id --output tsv)}"
      DESCRIPTOR="Microsoft.VisualStudio.Services.Claims.AadServicePrincipal;$TENANT_ID\\\\$SP_OBJECT_ID"

      ado() {
        az rest --only-show-errors --resource "$RESOURCE" "$@"
      }

      # The bit of a named action, from the namespace's own definition.
      bit() {
        ado --method get --url "$API/_apis/securitynamespaces/$1?api-version=7.1" \
          --query "value[0].actions[?name=='$2'].bit | [0]" --output tsv
      }

      # grant <namespace> <token> <allow bits>
      grant() {
        ado --method post --url "$API/_apis/accesscontrolentries/$1?api-version=7.1-preview.1" \
          --headers 'Content-Type=application/json' \
          --body "{\"token\":\"$2\",\"merge\":true,\"accessControlEntries\":[{\"descriptor\":\"$DESCRIPTOR\",\"allow\":$3,\"deny\":0}]}" \
          --output none
      }

      # add_to_organization <project entitlements JSON array>
      # An app that is already in the organization comes back as a failed operation, not an
      # error, so running the script again is safe.
      add_to_organization() {
        ado --method post --url "https://vsaex.dev.azure.com/$ORG/_apis/serviceprincipalentitlements?api-version=7.1-preview.1" \
          --headers 'Content-Type=application/json' \
          --body "{\"accessLevel\":{\"accountLicenseType\":\"express\"},\"servicePrincipal\":{\"origin\":\"aad\",\"originId\":\"$SP_OBJECT_ID\",\"subjectKind\":\"servicePrincipal\"},\"projectEntitlements\":$1}" \
          --output none
      }

      project_id() {
        local escaped=${1//\'/\\\'}
        ado --method get --url "$API/_apis/projects?\$top=1000&api-version=7.1" \
          --query "value[?name=='$escaped'].id | [0]" --output tsv
      }

      PROJECT_IDS=()
      for name in "$@"; do
        id=$(project_id "$name")
        if [ -z "$id" ] || [ "$id" = "None" ]; then
          echo "No project named '$name' in $ORG" >&2
          exit 1
        fi
        PROJECT_IDS+=("$id")
      done

      grant_service_hooks() {
        [ "$SERVICE_HOOKS" = 1 ] || return 0
        local allow=$(( $(bit "$HOOKS_NS" ViewSubscriptions) | $(bit "$HOOKS_NS" EditSubscriptions) ))
        for id in "${PROJECT_IDS[@]}"; do
          grant "$HOOKS_NS" "PublisherSecurity/$id" "$allow"
        done
      }
    BASH

    CONTRIBUTORS_BODY = <<~"BASH"
      #{COMMON}
      # Basic access, and the Contributors group of every project listed.
      entitlements=''
      for id in "${PROJECT_IDS[@]}"; do
        entitlements="${entitlements:+$entitlements,}{\\"group\\":{\\"groupType\\":\\"projectContributor\\"},\\"projectRef\\":{\\"id\\":\\"$id\\"}}"
      done
      add_to_organization "[$entitlements]"

      # Service Hooks (View and Edit subscriptions): only for instant CI gates and Boards triggers.
      grant_service_hooks

      echo "Done. Go back to Aixle Flow and press Verify."
    BASH

    CUSTOM_BODY = <<~"BASH"
      #{COMMON}
      # Basic access only; everything else is granted below, project by project, and nothing more.
      add_to_organization '[]'

      project_token_prefix='$PROJECT:vstfs:///Classification/TeamProject/'
      repo_read=$(bit "$GIT_NS" GenericRead)
      contribute=$(bit "$GIT_NS" GenericContribute)
      create_branch=$(bit "$GIT_NS" CreateBranch)
      pull_requests=$(bit "$GIT_NS" PullRequestContribute)
      work_read=$(bit "$CSS_NS" WORK_ITEM_READ)
      work_write=$(bit "$CSS_NS" WORK_ITEM_WRITE)
      view_builds=$(bit "$BUILD_NS" ViewBuilds)
      view_project=$(bit "$PROJECT_NS" GENERIC_READ)

      for id in "${PROJECT_IDS[@]}"; do
        # See the project at all.
        grant "$PROJECT_NS" "${project_token_prefix}$id" "$view_project"
        # Repos: read, contribute, create branches, contribute to pull requests.
        grant "$GIT_NS" "repoV2/$id" "$(( repo_read | contribute | create_branch | pull_requests ))"
        # Boards: view and edit work items, on the project's root area path.
        area=$(ado --method get --url "$API/$id/_apis/wit/classificationnodes/areas?\\$depth=0&api-version=7.1" --query identifier --output tsv)
        grant "$CSS_NS" "vstfs:///Classification/Node/$area" "$(( work_read | work_write ))"
        # Pipelines: view builds.
        grant "$BUILD_NS" "$id" "$view_builds"
      done

      # Service Hooks (View and Edit subscriptions): only for instant CI gates and Boards triggers.
      grant_service_hooks

      echo "Done. Go back to Aixle Flow and press Verify."
    BASH

    def initialize(organization:, tenant_id:, client_id:, flavor: "contributors", service_hooks: true)
      @organization = organization.to_s
      @tenant_id = tenant_id.to_s
      @client_id = client_id.to_s
      @flavor = flavor.to_s
      @service_hooks = service_hooks
      validate!
    end

    def to_s
      [ header, @flavor == "custom" ? CUSTOM_BODY : CONTRIBUTORS_BODY ].join("\n")
    end

    private

    def validate!
      unless @organization.match?(AzureDevopsInstallation::ORGANIZATION_SLUG)
        raise ValidationFailed, "'#{@organization}' is not a valid Azure DevOps organization name"
      end
      raise ValidationFailed, "Unknown permission set '#{@flavor}'" unless FLAVORS.include?(@flavor)

      [ @tenant_id, @client_id ].each do |value|
        raise ValidationFailed, "'#{value.to_s.truncate(40)}' is not a GUID" unless value.match?(GUID)
      end
    end

    def header
      <<~BASH
        #!/usr/bin/env bash
        # Lets the Entra app #{@client_id} work in the Azure DevOps organization #{@organization}.
        # Run it once as a Project Collection Administrator (az login first), naming the
        # projects agents work in:  ./aixle-azure-devops.sh "Project A" "Project B"
        # Read it first: it adds the app to the organization with a Basic license and
        # grants the permissions below on those projects.
        # Permission set: #{@flavor == 'custom' ? 'custom (only the permissions Aixle needs)' : 'Contributors group'}.
        set -euo pipefail

        ORG='#{@organization}'
        TENANT_ID='#{@tenant_id}'
        CLIENT_ID='#{@client_id}'
        SERVICE_HOOKS=#{@service_hooks ? 1 : 0}
        GIT_NS='#{PermissionCheck::GIT_NAMESPACE}'
        BUILD_NS='#{PermissionCheck::BUILD_NAMESPACE}'
        CSS_NS='#{PermissionCheck::CLASSIFICATION_NAMESPACE}'
        HOOKS_NS='#{PermissionCheck::SERVICE_HOOKS_NAMESPACE}'
        PROJECT_NS='#{PROJECT_NAMESPACE}'
      BASH
    end
  end
end
