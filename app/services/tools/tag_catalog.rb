# frozen_string_literal: true

module Tools
  # Single source of truth for how tool tags present in the UI tool pickers.
  #
  # Each entry declares, per tag:
  # - label:        human-readable name shown in the picker
  # - ui_visible:   whether the picker surfaces this tag at all (service and
  #                 provider-only tags stay hidden — they auto-inject, are
  #                 builder-bound, or are surfaced through a managed server)
  # - presentation: :group    — the picker shows ONE entry that attaches every
  #                             tool carrying the tag ("Board management")
  #                 :individual — the tools show one by one, grouped under the
  #                             label as a heading
  #
  # A tag not listed here is treated as hidden. A user_attachable tool that
  # matches no ui_visible group/individual tag falls through to the picker's
  # ungrouped list (see Registry.tag_catalog_for_pickers).
  module TagCatalog
    Entry = Struct.new(:tag, :label, :ui_visible, :presentation, keyword_init: true)

    ENTRIES = [
      Entry.new(tag: :board, label: "Board management", ui_visible: true, presentation: :group),
      Entry.new(tag: :messaging, label: "Messaging", ui_visible: true, presentation: :individual),
      Entry.new(tag: :slack, label: "Slack", ui_visible: false, presentation: :individual),
      Entry.new(tag: :coder, label: "Coder", ui_visible: false, presentation: :group),
      Entry.new(tag: :workflow_control, label: "Workflow control", ui_visible: false, presentation: :individual),
      Entry.new(tag: :async_results, label: "Async results", ui_visible: false, presentation: :individual),
      Entry.new(tag: :session_lifecycle, label: "Session lifecycle", ui_visible: false, presentation: :individual),
      Entry.new(tag: :repositories, label: "Repositories", ui_visible: false, presentation: :individual),
      # Read-only supervision of the OTHER sessions in the project. Its own tag
      # rather than the personal server's :sessions, so a user-audience tool can
      # never be resolved into a picker group.
      Entry.new(tag: :session_supervision, label: "Session supervision", ui_visible: true, presentation: :group),
      Entry.new(tag: :builder, label: "Aixle Builder", ui_visible: false, presentation: :individual)
    ].freeze

    BY_TAG = ENTRIES.index_by(&:tag).freeze

    class << self
      def entry(tag)
        BY_TAG[tag.to_sym]
      end

      def label(tag)
        entry(tag)&.label || tag.to_s.humanize
      end

      def ui_visible?(tag)
        entry(tag)&.ui_visible || false
      end

      def group?(tag)
        e = entry(tag)
        e&.ui_visible && e.presentation == :group
      end

      # Ordered, UI-facing entries (for serializing the catalog to the client).
      def ui_entries
        ENTRIES.select(&:ui_visible)
      end
    end
  end
end
