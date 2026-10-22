# frozen_string_literal: true

module Admin
  module FeatureFlagsHelper
    SOURCE_LABELS = { env: "ENV", company: "company override", global: "global value", default: "declared default",
                      unknown: "undeclared" }.freeze

    def feature_flag_value(value)
      case value
      when true then tag.span("on", class: "flag-value flag-value--on")
      when false then tag.span("off", class: "flag-value flag-value--off")
      else tag.span("not set", class: "flag-muted")
      end
    end

    def feature_flag_source(source) = SOURCE_LABELS.fetch(source, source.to_s)

    def feature_flag_badge(text, tone, title: nil) = tag.span(text, class: "flag-badge flag-badge--#{tone}", title: title)

    def feature_flag_audit_value(value)
      case value
      when true then "on"
      when false then "off"
      else "not set"
      end
    end
  end
end
