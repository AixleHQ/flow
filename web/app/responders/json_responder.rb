class JsonResponder < ActionController::Responder
  def api_behavior(*args, &block)
    case true
    when post?
      display(resource, status: :created)
    when put? || patch?
      display(resource, status: :ok)
    when get? && controller.paginated_resource?(resource)
      display(controller.paginated_response(resource, options))
    else
      super
    end
  end
end
