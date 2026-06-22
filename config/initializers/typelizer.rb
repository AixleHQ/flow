# frozen_string_literal: true

if ENV["RUBY_LSP"] == "1"
  return
end

Typelizer.configure do |config|
  config.output_dir = Rails.root.join("app/frontend/types/generated")
  config.types_import_path = "@/types/generated"
  config.null_strategy = :nullable
  config.comments = true

  config.properties_transformer = lambda { |properties|
    properties.map { |prop| prop.dup.tap { |p| p.name = prop.name.to_s.camelize(:lower) } }
  }

  config.serializer_model_mapper = lambda { |serializer|
    model_name = serializer.name.delete_suffix("Resource")
    model_name = "User" if model_name == "CurrentUser"
    model_name.safe_constantize
  }
end
