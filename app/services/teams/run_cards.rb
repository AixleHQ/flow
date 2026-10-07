# frozen_string_literal: true

module Teams
  # The Adaptive Cards behind "Run workflow" and /run (docs/design/teams-integration.md §20).
  module RunCards
    VERSION = "1.5"

    module_function

    # What a person not yet known to Aixle is shown instead of the workflows.
    def link(url)
      card(
        [ text("Link your Aixle account", weight: "Bolder"),
          text("Aixle Flow starts workflows as the Aixle user you are, with what that account may run. " \
               "Link your Teams account once; the link works for an hour.") ],
        [ { type: "Action.OpenUrl", title: "Link my Aixle account", url: url } ]
      )
    end

    # A form for the message-action dialog (submitted as composeExtension/submitAction)
    # or, with `execute`, for the /run card (an adaptiveCard/action invoke).
    def picker(entries, data:, execute: false, notes: nil)
      submit = execute ? { type: "Action.Execute", verb: "run" } : { type: "Action.Submit" }
      card(
        [ text("Run a workflow", weight: "Bolder"),
          { type: "Input.ChoiceSet", id: "workflow", label: "Workflow", isRequired: true,
            errorMessage: "Choose a workflow", style: "filtered", value: entries.first&.key,
            choices: entries.map { |entry| { title: entry.title, value: entry.key } } },
          { type: "Input.Text", id: "notes", label: "Notes (optional)", isMultiline: true, maxLength: 2000, value: notes }.compact ],
        [ submit.merge(title: "Run", data: data) ]
      )
    end

    def started(entry, run)
      card([ text("▶️ Started #{entry.workflow.name} · run ##{run.id}", weight: "Bolder"),
             text("Its status card follows the run in the conversation.", isSubtle: true) ],
           [ { type: "Action.OpenUrl", title: "Open run", url: Chat::RunFailure.url(run) } ])
    end

    def notice(message)
      card([ text(message) ], [])
    end

    def text(value, **options) = { type: "TextBlock", text: value, wrap: true, **options }

    def card(body, actions)
      { "$schema" => "http://adaptivecards.io/schemas/adaptive-card.json", type: "AdaptiveCard", version: VERSION,
        body: body, actions: actions }
    end

    def attachment(card) = { contentType: "application/vnd.microsoft.card.adaptive", content: card }
  end
end
