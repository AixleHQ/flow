# frozen_string_literal: true

# Plain-text labels written by agents through the MCP tools. A model sometimes
# HTML-escapes its own tool arguments, and "Plan &amp; release next batch" then
# shows literally and reaches every later session's context (prod transcripts,
# 2026-10-16). Markdown bodies are left alone: instructions legitimately write
# `&lt;` when they talk about escaping.
module DecodesHtmlEntities
  extend ActiveSupport::Concern

  class_methods do
    def decodes_html_entities(*attributes)
      normalizes(*attributes, with: ->(text) { CGI.unescapeHTML(text) })
    end
  end
end
