# frozen_string_literal: true

class CreateTemplateMarketplaceTables < ActiveRecord::Migration[8.1]
  def change
    # Publishers, from the templates repository's namespaces.yaml. A template's
    # identity is namespace/slug, so two publishers can each have a
    # "code-reviewer-agent".
    create_table :catalog_namespaces do |t|
      t.string :name, null: false, index: { unique: true }
      t.string :display_name, null: false
      t.string :url
      t.boolean :verified, null: false, default: false
      t.string :owners, array: true, null: false, default: []
      t.datetime :synced_at, null: false
      t.timestamps
    end

    # This installation's mirror of the public templates repository. Global, not
    # tenant data — like connectors and catalog_skills.
    create_table :catalog_templates do |t|
      t.string :namespace, null: false
      t.string :slug, null: false
      t.integer :version, null: false
      t.string :name, null: false
      t.text :summary
      t.string :kind, null: false
      t.string :categories, array: true, null: false, default: []
      t.integer :format_version, null: false
      t.jsonb :definition, null: false, default: {}
      # path → { "base64" => …, "sha256" => …, "size" => … }
      t.jsonb :files, null: false, default: {}
      t.text :readme
      t.text :setup_markdown
      t.string :commit_sha, null: false
      t.string :package_digest, null: false
      t.boolean :installable, null: false, default: true
      t.datetime :revoked_at
      t.text :revocation_reason
      t.integer :install_count, null: false, default: 0
      t.datetime :synced_at, null: false
      t.timestamps

      t.index [ :namespace, :slug ], unique: true
      t.index :kind
    end

    # Provenance of every install: which reviewed package went into which project.
    create_table :template_installs do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :installed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :namespace, null: false
      t.string :slug, null: false
      t.integer :version, null: false
      t.string :commit_sha, null: false
      t.string :package_digest, null: false
      t.string :idempotency_key, null: false
      t.timestamps

      t.index [ :installed_by_id, :idempotency_key ], unique: true
      t.index [ :namespace, :slug ]
    end

    # The post-install checklist. One row per thing left to do; `ref` is stable
    # within an install so a retry updates its item instead of adding one.
    create_table :template_setup_items do |t|
      t.references :template_install, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :ref, null: false
      t.string :status, null: false, default: "pending"
      t.integer :position, null: false, default: 0
      t.jsonb :detail, null: false, default: {}
      t.timestamps

      t.index [ :template_install_id, :ref ], unique: true
    end
  end
end
