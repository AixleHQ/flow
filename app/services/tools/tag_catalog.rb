# frozen_string_literal: true

module Tools
  # Single source of truth for how tool tags present in the UI tool pickers
  # (workflow Base Resources + the step session editor).
  #
  # Each entry declares, per tag:
  # - label:      human-readable name shown in the picker
  # - ui_visible: whether the picker offers this tag. A visible tag becomes ONE
  #               picker entry that attaches every session tool carrying it
  #               ("Board management", "Slack") — its members are never offered
  #               one by one. Hidden tags stay out of the picker entirely: they
  #               auto-inject, are builder-bound, or are surfaced through a
  #               managed server.
  #
  # A tag not listed here is treated as hidden. A user_attachable session tool
  # that matches no visible tag falls through to the picker's ungrouped list.
  #
  # A tool must not carry two visible tags — it would land in two picker groups
  # whose selections fight over the same ids (asserted in Tools::RegistryTest).
  module TagCatalog
    Entry = Struct.new(:tag, :label, :ui_visible, keyword_init: true)

    ENTRIES = [
      Entry.new(tag: :board, label: "Board management", ui_visible: true),
      Entry.new(tag: :slack, label: "Slack", ui_visible: true),
      Entry.new(tag: :coder, label: "Coder", ui_visible: true),
      Entry.new(tag: :azure_devops, label: "Azure DevOps", ui_visible: true),
      Entry.new(tag: :assets, label: "Assets", ui_visible: true),
      # Read-only supervision of the OTHER sessions in the project. Its own tag
      # rather than the personal server's :sessions, so a user-audience tool can
      # never be resolved into a picker group.
      Entry.new(tag: :session_supervision, label: "Session supervision", ui_visible: true),
      # Umbrella over every chat provider. The picker groups by provider
      # (:slack), so this one stays hidden — otherwise the Slack tools would be
      # offered twice, under two competing entries.
      Entry.new(tag: :messaging, label: "Messaging", ui_visible: false),
      Entry.new(tag: :workflow_control, label: "Workflow control", ui_visible: false),
      Entry.new(tag: :async_results, label: "Async results", ui_visible: false),
      Entry.new(tag: :session_lifecycle, label: "Session lifecycle", ui_visible: false),
      Entry.new(tag: :repositories, label: "Repositories", ui_visible: false),
      Entry.new(tag: :builder, label: "Aixle Builder", ui_visible: false)
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

      # Ordered, UI-facing entries — one picker group each.
      def ui_entries
        ENTRIES.select(&:ui_visible)
      end
    end
  end
end
