# frozen_string_literal: true

module AwsOidc
  # The `sub` claim (docs/design/aws-oidc-integration.md §5.3). Ids only: slugs can be
  # renamed, and a renamed project must neither lose its trust nor match a pattern
  # written for something else.
  module Subject
    module_function

    # A draft is a hidden copy of its workflow with its own ids. The source ids keep a
    # draft's test run inside the trust written for the workflow; the `draft:` prefix
    # keeps unsaved changes out of it unless the policy names drafts too.
    def for_step(step)
      workflow = step.workflow
      return "workflow:#{workflow.id}:step:#{step.id}" if workflow.draft_of_id.nil?

      source_step = step.origin_step_id || "new-#{step.id}"
      "draft:workflow:#{workflow.draft_of_id}:step:#{source_step}"
    end

    def for_verify(integration)
      "verify:integration:#{integration.id}"
    end
  end
end
