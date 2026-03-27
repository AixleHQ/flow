# Story 4.1: Config Items CRUD with Type Toggle

Status: review

## Story

As a company/project admin,
I want to create and manage config items with a type selector (Secret/Variable),
So that I can configure both sensitive and non-sensitive values in one place.

## Acceptance Criteria

1. **AC1:** Unified "Config Items" page exists (not separate pages for secrets/variables)
2. **AC2:** Create form has fields: Name, Value, Description, Type toggle (Secret/Variable), Scope selector (Company/Project)
3. **AC3:** When type = Secret: value encrypted before save, value field cleared after save (cannot be viewed again)
4. **AC4:** When type = Variable: value stored in plain text, value visible and editable
5. **AC5:** Can edit name, description for both types
6. **AC6:** Can edit value for both types (Secrets: new value encrypted, old value overwritten)
7. **AC7:** Can delete config items with confirmation dialog
8. **AC8:** Name must be unique within scope (company OR project)

## Tasks / Subtasks

- [x] Task 1: Create ConfigItem model (AC: 2, 3, 4, 8)
  - [x] 1.1: Generate migration with columns: name, value, encrypted_value, description, item_type, scope_type, scope_id
  - [x] 1.2: Create ConfigItem model with Enumerize for item_type and scope_type
  - [x] 1.3: Implement conditional encryption (only for secrets)
  - [x] 1.4: Add validations (name uniqueness within scope)
  - [x] 1.5: Add polymorphic scope association (Company/Project)

- [x] Task 2: Create API endpoints (AC: 1, 2, 5, 6, 7)
  - [x] 2.1: Create ConfigItemsController with CRUD actions
  - [x] 2.2: Create ConfigItemPolicy (Pundit) for authorization
  - [x] 2.3: Create ConfigItemSerializer (hide encrypted values)
  - [x] 2.4: Add routes nested under company and project

- [x] Task 3: Create tests (AC: all)
  - [x] 3.1: Controller tests for CRUD operations

## Dev Notes

### Model Design Decision: Single Model with Enumerize (NOT STI)

**Rationale:**
- Secret and Variable differ only in encryption/visibility, not in associations or fundamental behavior
- UI displays both in unified table — STI adds unnecessary complexity
- Enumerize already used in project (see `Project.state`)
- Less code: single model, controller, serializer

### Database Schema

```ruby
# db/migrate/XXXXXX_create_config_items.rb
class CreateConfigItems < ActiveRecord::Migration[8.0]
  def change
    create_table :config_items do |t|
      t.string :name, null: false
      t.text :value                    # Plain text for variables
      t.text :encrypted_value          # Encrypted for secrets
      t.text :description
      t.integer :item_type, null: false, default: 1  # 0=secret, 1=variable
      t.string :scope_type, null: false  # 'Company' or 'Project'
      t.bigint :scope_id, null: false

      t.timestamps
    end

    # Unique name within scope
    add_index :config_items, [:scope_type, :scope_id, :name], unique: true
    add_index :config_items, [:scope_type, :scope_id]
  end
end
```

### Model Implementation

```ruby
# app/models/config_item.rb
class ConfigItem < ApplicationRecord
  extend Enumerize

  # Enumerize for type (adds scopes: with_item_type(:secret), with_scope_type(:company))
  enumerize :item_type, in: %i[secret variable], default: :variable, predicates: true, scope: true
  enumerize :scope_type, in: %i[company project], predicates: { prefix: true }, scope: true

  # Polymorphic scope
  belongs_to :scope, polymorphic: true

  # Validations
  validates :name, presence: true,
                   format: { with: /\A[A-Z][A-Z0-9_]*\z/, message: "must be uppercase with underscores (e.g., API_KEY)" }
  validates :name, uniqueness: { scope: [:scope_type, :scope_id], message: "already exists in this scope" }
  validates :item_type, presence: true
  validates :scope_type, presence: true
  validates :scope_id, presence: true

  # Value must be present on create
  validate :value_present_on_create, on: :create

  # Callbacks
  before_save :encrypt_value_if_secret

  # Scopes (enumerize adds: with_item_type, with_scope_type)
  scope :for_company, ->(company) { where(scope_type: 'Company', scope_id: company.id) }
  scope :for_project, ->(project) { where(scope_type: 'Project', scope_id: project.id) }

  # Get display value (masked for secrets)
  def display_value
    secret? ? '••••••••' : value
  end

  # Set value (handles encryption for secrets)
  def value=(val)
    if secret?
      self.encrypted_value = encrypt(val) if val.present?
      super(nil)  # Clear plain value
    else
      self.encrypted_value = nil
      super(val)
    end
  end

  # Get decrypted value (for container injection only)
  def decrypted_value
    secret? ? decrypt(encrypted_value) : value
  end

  private

  def value_present_on_create
    if secret?
      errors.add(:value, "can't be blank") if encrypted_value.blank?
    else
      errors.add(:value, "can't be blank") if value.blank?
    end
  end

  def encrypt_value_if_secret
    # Already handled in value= setter
  end

  def encrypt(plain_text)
    return nil if plain_text.blank?
    encryptor.encrypt_and_sign(plain_text)
  end

  def decrypt(cipher_text)
    return nil if cipher_text.blank?
    encryptor.decrypt_and_verify(cipher_text)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(encryption_key)
  end

  def encryption_key
    Settings.encryption.config_items_key.to_s.ljust(32, "0")[0..31]
  end
end
```

### Controller Pattern

```ruby
# app/controllers/api/v1/company/config_items_controller.rb
module Api::V1::Company
  class ConfigItemsController < BaseController
    def index
      items = current_company_scope.ransack(params[:q]).result
      respond_with paginate(items)
    end

    def create
      item = current_company_scope.new(config_item_params)
      item.save
      respond_with item
    end

    def update
      item = current_company_scope.find(params[:id])
      item.update(config_item_params)
      respond_with item
    end

    def destroy
      item = current_company_scope.find(params[:id])
      item.destroy
      respond_with item
    end

    private

    def current_company_scope
      ConfigItem.for_company(current_company)
    end

    def config_item_params
      params.require(:config_item).permit(:name, :value, :description, :item_type)
            .merge(scope_type: 'Company', scope_id: current_company.id)
    end
  end
end
```

### Serializer

```ruby
# app/serializers/config_item_serializer.rb
class ConfigItemSerializer < ApplicationSerializer
  attributes :id, :name, :description, :item_type, :scope_type, :scope_id,
             :created_at, :updated_at

  # Value: show actual for variables, masked for secrets
  attribute :value do |item|
    item.display_value
  end

  # Flag for UI to know if value is editable
  attribute :value_editable do |item|
    item.variable?
  end
end
```

### API Routes

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    namespace :company do
      resources :config_items, except: [:show]

      resources :projects do
        resources :config_items, except: [:show]
      end
    end
  end
end
```

### Settings Configuration

Add to `config/settings.yml`:
```yaml
encryption:
  config_items_key: <%= ENV['CONFIG_ITEMS_ENCRYPTION_KEY'] || Rails.application.credentials.config_items_key %>
```

### Project Structure Notes

- Model: `web/app/models/config_item.rb`
- Migration: `web/db/migrate/XXXXXX_create_config_items.rb`
- Controllers:
  - `web/app/controllers/api/v1/company/config_items_controller.rb` (company-level)
  - `web/app/controllers/api/v1/company/projects/config_items_controller.rb` (project-level)
- Policy: `web/app/policies/api/v1/company/config_items_policy.rb`
- Serializer: `web/app/serializers/config_item_serializer.rb`
- Tests:
  - `web/test/controllers/api/v1/company/config_items_controller_test.rb`
  - `web/test/controllers/api/v1/company/projects/config_items_controller_test.rb`

### References

- [Source: ai/epics.md#Epic 4: Config Items]
- [Source: ai/architecture.md#Implementation Patterns]
- [Source: web/app/models/project.rb] — Enumerize usage pattern
- [Source: web/app/models/agent_credential.rb] — Encryption pattern

## Dev Agent Record

### Agent Model Used

Claude Opus 4

### Debug Log References

N/A

### Completion Notes List

- Created ConfigItem model with Enumerize for item_type (secret/variable)
- Implemented conditional encryption using ActiveSupport::MessageEncryptor
- Created CRUD controllers for both company-level and project-level config items
- Added Pundit policies: company admins can manage company items, project owners can manage project items
- Created ConfigItemSerializer with masked values for secrets
- Added comprehensive controller tests (40+ test cases)
- Added encryption key to settings.yml
- Added config_items association to Company and Project models

### File List

- web/db/migrate/20260202100000_create_config_items.rb (new)
- web/app/models/config_item.rb (new)
- web/app/models/company.rb (modified - added association)
- web/app/models/project.rb (modified - added association)
- web/app/controllers/api/v1/company/config_items_controller.rb (new)
- web/app/controllers/api/v1/company/projects/config_items_controller.rb (new)
- web/app/policies/api/v1/company/config_items_policy.rb (new)
- web/app/policies/api/v1/company/projects/config_items_policy.rb (new)
- web/app/serializers/config_item_serializer.rb (new)
- web/config/routes.rb (modified - added routes)
- web/config/settings.yml (modified - added encryption key)
- web/test/factories/config_items.rb (new)
- web/test/controllers/api/v1/company/config_items_controller_test.rb (new)
- web/test/controllers/api/v1/company/projects/config_items_controller_test.rb (new)
