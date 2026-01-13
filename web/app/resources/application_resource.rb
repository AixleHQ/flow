# Base class for all MCP resources
class ApplicationResource < ActionResource::Base
  def auth_token
    @auth_token ||= headers["auth-token"]
  end

  def current_specification_user
    @current_specification_user ||= SpecificationUser.find_by!(mcp_token: auth_token)
  end

  def current_specification
    @current_specification ||= current_specification_user.specification
  end

  def current_user
    @current_user ||= current_specification_user.user
  end

  def latest_version
    @latest_version ||= current_specification.latest_version
  end

  def serialize(object)
    ActiveModelSerializers::SerializableResource.new(object).as_json
  end
end
