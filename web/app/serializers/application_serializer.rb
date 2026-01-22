class ApplicationSerializer < ActiveModel::Serializer
  def include_associations
    !@instance_options[:skip_associations]
  end
end
