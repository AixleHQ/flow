# frozen_string_literal: true

# SCIM 2.0 as a service provider (CAP-6, AD-10).
#
# A customer's directory authenticates with a per-company bearer token; which
# company it belongs to is what scopes every read and write. The token is the
# only thing that decides the tenant — never a path segment or a payload field.
Rails.application.config.to_prepare do
  Scimitar.engine_configuration = Scimitar::EngineConfiguration.new(
    token_authenticator: lambda do |token, _options|
      configuration = ScimConfiguration.authenticate(token)
      next false if configuration.nil?

      configuration.touch_seen!
      # Stashed for the controllers: the request is scoped to this company and
      # nothing else can widen it.
      ScimCurrent.configuration = configuration
      true
    end,

    # Microsoft Entra sends a few non-standard shapes; scimitar's own
    # compatibility switches handle them, and turning them off would mean
    # rejecting the directory most of our customers actually run.
    optional_value_fields_required: false
  )
end
