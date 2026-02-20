require "active_model_serializers"

module Adapters
  class ItemsDataAdapter < ActiveModelSerializers::Adapter::Json
    LIST_ROOT_KEY = :items
    DETAILS_ROOT_KEY = :data

    def root
      serializer.is_a?(ActiveModel::Serializer::CollectionSerializer) ? LIST_ROOT_KEY : DETAILS_ROOT_KEY
    end
  end
end


Rails.application.config.to_prepare do
  ActiveModelSerializers::Adapter.register(:items_data_adapter, Adapters::ItemsDataAdapter)
  ActiveModelSerializers.config.adapter = :items_data_adapter
  # ActiveModelSerializers.config.adapter = :json
end
