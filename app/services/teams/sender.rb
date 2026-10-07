# frozen_string_literal: true

module Teams
  # Who a Teams sender is in Aixle (docs/design/teams-integration.md §9): the
  # account that signs in with that Microsoft account, or the one that linked it,
  # as long as that account may still sign in. Never by email: Entra does not
  # verify addresses.
  module Sender
    module_function

    def user_id(tenant_id, object_id)
      user(tenant_id, object_id)&.id
    end

    def user(tenant_id, object_id)
      return nil if object_id.blank?

      ids = UserIdentity.joins(:identity_provider).where(identity_providers: { kind: "microsoft" })
                        .where(subject: object_id).pluck(:user_id)
      ids << ChatIdentity.user_id_for(provider: Chat::TeamsProvider::KEY, workspace_id: tenant_id, external_user_id: object_id)
      User.authenticatable.where(id: ids.compact).min_by { |user| ids.index(user.id) }
    end
  end
end
