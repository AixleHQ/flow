# frozen_string_literal: true

# EXPAND phase of AD-14. Seeds the two deployment providers that exist today,
# gives every company an explicit policy row for each (absent row = denied, so
# the seeding is what keeps behaviour identical on day one), and backfills one
# identity per existing credential.
#
# Local AR classes: a migration must not depend on app models, which move.
class BackfillFederatedIdentity < ActiveRecord::Migration[8.1]
  class MigrationIdentityProvider < ActiveRecord::Base
    self.table_name = "identity_providers"
  end

  class MigrationCompany < ActiveRecord::Base
    self.table_name = "companies"
  end

  class MigrationCompanyAuthPolicy < ActiveRecord::Base
    self.table_name = "company_auth_policies"
  end

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationUserIdentity < ActiveRecord::Base
    self.table_name = "user_identities"
  end

  def up
    now = Time.current

    password = MigrationIdentityProvider.create!(
      kind: "password", scope: "deployment", name: "Password", created_at: now, updated_at: now
    )
    google = MigrationIdentityProvider.create!(
      kind: "google", scope: "deployment", name: "Google", created_at: now, updated_at: now
    )

    MigrationCompany.pluck(:id).each do |company_id|
      [ password, google ].each do |provider|
        MigrationCompanyAuthPolicy.create!(
          company_id: company_id, identity_provider_id: provider.id,
          enabled: true, created_at: now, updated_at: now
        )
      end
    end

    # A local password has no external subject; the user's own id is the stable
    # one. Unique per provider, which is all (provider, subject) requires.
    MigrationUser.where.not(password_digest: nil).pluck(:id, :email).each do |id, email|
      MigrationUserIdentity.create!(
        user_id: id, identity_provider_id: password.id, subject: id.to_s,
        email: email, email_verified: true, created_at: now, updated_at: now
      )
    end

    MigrationUser.where(provider: "google").where.not(uid: nil).pluck(:id, :uid, :email).each do |id, uid, email|
      MigrationUserIdentity.create!(
        user_id: id, identity_provider_id: google.id, subject: uid,
        email: email, email_verified: true, created_at: now, updated_at: now
      )
    end
  end

  def down
    MigrationUserIdentity.delete_all
    MigrationCompanyAuthPolicy.delete_all
    MigrationIdentityProvider.delete_all
  end
end
