# frozen_string_literal: true

module Chat
  # `@<bot> connect <code>` in the channel a code names connects that channel
  # to the company that asked for it (docs/design/shared-chat-workspaces.md §8.2–8.3).
  #
  # Every refusal gets the same answer, shown only to whoever posted it where the
  # messenger allows, so nobody in the channel learns which companies exist and a
  # stream of bad codes is no noise; the person who asked for the code sees the
  # reason on the code itself in Aixle. Only a connection is announced to all.
  module ChannelConnect
    # Only the bare word or the word and a code: "connect the repo to staging" is
    # a request for a workflow, not for this.
    REQUEST = /\A\/?connect(?:\s+#{ChatConnectCode::PREFIX}\S*)?\s*\z/i
    UNUSABLE = "This code is not valid here or has expired. Request a new one in Aixle."
    DIRECT = "Post the code in the channel you want to connect, not in a direct chat."

    Outcome = Data.define(:code, :connection, :binding, :already_connected)

    module_function

    def request?(event)
      event.data.to_h["text"].to_s.strip.match?(REQUEST)
    end

    # True once answered.
    def call(event)
      provider = Chat.provider_for(event)
      return false if provider.nil?

      code = ChatConnectCode.extract(event.data.to_h["text"])
      return answer(provider, event, hint(provider)) if code.nil?

      if event.data.to_h.dig("conversation", "type") == "direct"
        refuse!(code, "Posted in a direct chat, not in a channel")
        return answer(provider, event, DIRECT)
      end

      outcome = redeem(provider, event, code)
      return answer(provider, event, UNUSABLE) if outcome.nil?

      message_id = provider.reply(event, confirmation(provider, event, outcome))
      record_confirmation(provider, event, outcome, message_id)
      true
    rescue StandardError => e
      Rails.logger.error("[Chat::ChannelConnect] event ##{event&.id}: #{e.class}: #{e.message}")
      false
    end

    def redeem(provider, event, code)
      ChatConnectCode.transaction do
        record = ChatConnectCode.lock.find_by(code_digest: ChatConnectCode.digest(code))
        reason = refusal(record, provider)
        if reason
          record&.update!(failure_reason: reason) unless record&.redeemed_at
          next nil
        end

        integration = company_install(event, record.company_id)
        conversation = integration && provider.conversation_for(event, integration)
        if conversation.nil?
          record.update!(failure_reason: "Posted in a workspace this company has not connected")
          next nil
        end
        mismatch = record.channel_mismatch(conversation)
        if mismatch
          record.update!(failure_reason: mismatch)
          next nil
        end

        connect(record, conversation, event)
      end
    end

    def refusal(record, provider)
      return "unknown" if record.nil?
      return "Already used" if record.redeemed_at
      return "Expired" if record.expires_at <= Time.current
      return "Posted in #{provider.label}, but the code is for #{Chat.provider(record.provider)&.label}" if record.provider != provider.key

      nil
    end

    # The code's company's own install of the workspace the message came from:
    # any company that connected it may connect its channels.
    def company_install(event, company_id)
      heard_by = Integration.find_by(id: event.data.to_h["integration_id"])
      return nil if heard_by.nil?

      heard_by.chat_peers.active.find_by(company_id: company_id)
    end

    def connect(record, conversation, event)
      actor = event.data.to_h["actor"].to_h
      connection = ChatChannelConnection.find_or_initialize_by(chat_conversation: conversation, company_id: record.company_id)
      already = connection.persisted?
      unless already
        connection.assign_attributes(requested_by: record.requested_by, posted_by_external_id: actor["id"],
                                     posted_by_name: actor["name"])
        connection.save!
      end
      binding = bind_trigger(record, conversation)
      record.update!(redeemed_at: Time.current, chat_channel_connection: connection, failure_reason: nil)
      Outcome.new(code: record, connection: connection, binding: binding, already_connected: already)
    end

    # A code asked for on behalf of one trigger points that trigger at the
    # channel. Switching it on stays its owner's call.
    def bind_trigger(record, conversation)
      binding = record.trigger_binding
      return nil unless binding&.chat? && binding.project&.company_id == record.company_id &&
                        binding.chat_provider == conversation.provider

      binding.update(chat_conversation: conversation) ? binding : nil
    end

    def record_confirmation(provider, event, outcome, message_id)
      return if message_id.nil? || outcome.already_connected

      outcome.connection.update_columns(confirmation_message_id: message_id,
                                        confirmation_url: provider.permalink(event, message_id))
      ChatMessage.record!(conversation: outcome.connection.chat_conversation, message_id: message_id,
                          company_id: outcome.connection.company_id)
    end

    def refuse!(code, reason)
      ChatConnectCode.where(code_digest: ChatConnectCode.digest(code), redeemed_at: nil).update_all(failure_reason: reason)
    end

    def answer(provider, event, text)
      provider.reply_privately(event, text)
      true
    end

    def hint(provider)
      "To connect this channel, request a code in Aixle (Integrations → #{provider.label} → Connect a channel, " \
        "or from a chat trigger), then post it here."
    end

    # Names the company and what starts it, and nobody: the channel may hold
    # guests and other organizations, and the trace is the company.
    def confirmation(provider, event, outcome)
      company = provider.strong(outcome.code.company.name)
      first = outcome.already_connected ? "This channel was already connected to #{company}." : "This channel is now connected to #{company}."
      [ first, purpose(provider, event, outcome, company) ].join("\n")
    end

    def purpose(provider, event, outcome, company)
      binding = outcome.binding
      return "#{company}'s workflows can post here." if binding.nil?

      command = Chat::HelpCatalog.command(binding)
      asked = command ? "#{provider.bot_mention(event)} #{provider.escape(command)}" : "a mention of #{provider.bot_mention(event)}"
      "#{asked} here starts one of #{company}'s workflows."
    end
  end
end
