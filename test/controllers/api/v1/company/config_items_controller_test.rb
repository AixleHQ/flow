# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::ConfigItemsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @other_company = create(:company, email_domain: "other.com")

    @variable = @company.config_items.create!(
      name: "BASE_URL",
      value: "https://api.example.com",
      description: "API Base URL",
      item_type: :variable
    )

    @secret = @company.config_items.new(
      name: "API_KEY",
      description: "External API Key",
      item_type: :secret
    )
    @secret.value = "super_secret_123"
    @secret.save!
  end

  # ====== INDEX Tests ======

  test "#index returns company config items for admin" do
    sign_in @admin

    get :index

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 2 }
    names = json["items"].map { |i| i["name"] }
    assert { names.include?("BASE_URL") }
    assert { names.include?("API_KEY") }
  end

  test "#index masks secret values" do
    sign_in @admin

    get :index

    assert_response :success
    json = response.parsed_body
    secret_item = json["items"].find { |i| i["name"] == "API_KEY" }
    assert { secret_item["value"] == "••••••••" }
    assert { secret_item["value_editable"] == false }
  end

  test "#index shows variable values" do
    sign_in @admin

    get :index

    assert_response :success
    json = response.parsed_body
    variable_item = json["items"].find { |i| i["name"] == "BASE_URL" }
    assert { variable_item["value"] == "https://api.example.com" }
    assert { variable_item["value_editable"] == true }
  end

  test "#index does not return other company items" do
    other_item = @other_company.config_items.create!(
      name: "OTHER_VAR",
      value: "other_value",
      item_type: :variable
    )
    sign_in @admin

    get :index

    assert_response :success
    json = response.parsed_body
    names = json["items"].map { |i| i["name"] }
    refute { names.include?("OTHER_VAR") }
  end

  test "#index requires admin role" do
    sign_in @employee

    get :index

    assert_response :forbidden
  end

  test "#index requires authentication" do
    get :index

    assert_response :unauthorized
  end

  # ====== CREATE Tests ======

  test "#create creates variable" do
    sign_in @admin

    assert_difference("ConfigItem.count") do
      post :create, params: {
        config_item: {
          name: "NEW_VARIABLE",
          value: "new_value",
          description: "New variable",
          item_type: "variable"
        }
      }
    end

    assert_response :created
    json = response.parsed_body
    item = ConfigItem.find(json["data"]["id"])
    assert { item.name == "NEW_VARIABLE" }
    assert { item.value == "new_value" }
    assert { item.variable? }
    assert { item.scope == @company }
  end

  test "#create creates secret with encrypted value" do
    sign_in @admin

    assert_difference("ConfigItem.count") do
      post :create, params: {
        config_item: {
          name: "NEW_SECRET",
          value: "secret_value",
          description: "New secret",
          item_type: "secret"
        }
      }
    end

    assert_response :created
    json = response.parsed_body
    item = ConfigItem.find(json["data"]["id"])
    assert { item.name == "NEW_SECRET" }
    assert { item.secret? }
    assert { item.value.nil? } # Plain value should be nil
    assert { item.encrypted_value.present? } # Encrypted value should exist
    assert { item.decrypted_value == "secret_value" } # Can decrypt
    assert { json["data"]["value"] == "••••••••" } # Response shows masked
  end

  test "#create validates name format" do
    sign_in @admin

    assert_no_difference("ConfigItem.count") do
      post :create, params: {
        config_item: {
          name: "invalid-name",
          value: "value",
          item_type: "variable"
        }
      }
    end

    assert_response :unprocessable_entity
    json = response.parsed_body
    assert { json["errors"]["name"].present? }
  end

  test "#create validates name uniqueness within scope" do
    sign_in @admin

    assert_no_difference("ConfigItem.count") do
      post :create, params: {
        config_item: {
          name: "BASE_URL", # Already exists
          value: "duplicate",
          item_type: "variable"
        }
      }
    end

    assert_response :unprocessable_entity
    json = response.parsed_body
    assert { json["errors"]["name"].present? }
  end

  test "#create requires value" do
    sign_in @admin

    assert_no_difference("ConfigItem.count") do
      post :create, params: {
        config_item: {
          name: "NO_VALUE",
          item_type: "variable"
        }
      }
    end

    assert_response :unprocessable_entity
    json = response.parsed_body
    assert { json["errors"]["value"].present? }
  end

  test "#create requires admin role" do
    sign_in @employee

    assert_no_difference("ConfigItem.count") do
      post :create, params: {
        config_item: {
          name: "NEW_VAR",
          value: "value",
          item_type: "variable"
        }
      }
    end

    assert_response :forbidden
  end

  test "#create requires authentication" do
    assert_no_difference("ConfigItem.count") do
      post :create, params: {
        config_item: {
          name: "NEW_VAR",
          value: "value",
          item_type: "variable"
        }
      }
    end

    assert_response :unauthorized
  end

  # ====== UPDATE Tests ======

  test "#update updates variable value" do
    sign_in @admin

    patch :update, params: {
      id: @variable.id,
      config_item: {
        value: "new_url"
      }
    }

    assert_response :success
    @variable.reload
    assert { @variable.value == "new_url" }
  end

  test "#update updates variable name and description" do
    sign_in @admin

    patch :update, params: {
      id: @variable.id,
      config_item: {
        name: "NEW_NAME",
        description: "New description"
      }
    }

    assert_response :success
    @variable.reload
    assert { @variable.name == "NEW_NAME" }
    assert { @variable.description == "New description" }
  end

  test "#update updates secret value (re-encrypts)" do
    sign_in @admin
    old_encrypted = @secret.encrypted_value

    patch :update, params: {
      id: @secret.id,
      config_item: {
        value: "new_secret_value"
      }
    }

    assert_response :success
    @secret.reload
    assert { @secret.encrypted_value != old_encrypted }
    assert { @secret.decrypted_value == "new_secret_value" }
  end

  test "#update cannot change item from another company" do
    other_item = @other_company.config_items.create!(
      name: "OTHER_VAR",
      value: "other_value",
      item_type: :variable
    )
    sign_in @admin

    patch :update, params: {
      id: other_item.id,
      config_item: { value: "hacked" }
    }

    assert_response :not_found
  end

  test "#update requires admin role" do
    sign_in @employee

    patch :update, params: {
      id: @variable.id,
      config_item: { value: "hacked" }
    }

    assert_response :forbidden
  end

  test "#update requires authentication" do
    patch :update, params: {
      id: @variable.id,
      config_item: { value: "hacked" }
    }

    assert_response :unauthorized
  end

  # ====== DESTROY Tests ======

  test "#destroy removes config item" do
    sign_in @admin

    assert_difference("ConfigItem.count", -1) do
      delete :destroy, params: { id: @variable.id }
    end

    assert_response :no_content
    assert { ConfigItem.find_by(id: @variable.id).nil? }
  end

  test "#destroy cannot delete item from another company" do
    other_item = @other_company.config_items.create!(
      name: "OTHER_VAR",
      value: "other_value",
      item_type: :variable
    )
    sign_in @admin

    assert_no_difference("ConfigItem.count") do
      delete :destroy, params: { id: other_item.id }
    end

    assert_response :not_found
  end

  test "#destroy requires admin role" do
    sign_in @employee

    assert_no_difference("ConfigItem.count") do
      delete :destroy, params: { id: @variable.id }
    end

    assert_response :forbidden
  end

  test "#destroy requires authentication" do
    assert_no_difference("ConfigItem.count") do
      delete :destroy, params: { id: @variable.id }
    end

    assert_response :unauthorized
  end

  # ====== Response Format Tests ======

  test "#create returns expected fields" do
    sign_in @admin

    post :create, params: {
      config_item: {
        name: "RESPONSE_TEST",
        value: "test_value",
        description: "Test description",
        item_type: "variable"
      }
    }

    assert_response :created
    json = response.parsed_body
    data = json["data"]
    assert { data["id"].present? }
    assert { data["name"] == "RESPONSE_TEST" }
    assert { data["value"] == "test_value" }
    assert { data["description"] == "Test description" }
    assert { data["item_type"] == "variable" }
    assert { data["scope_type"] == "Company" }
    assert { data["scope_id"] == @company.id }
    assert { data["value_editable"] == true }
    assert { data["created_at"].present? }
    assert { data["updated_at"].present? }
  end
end
