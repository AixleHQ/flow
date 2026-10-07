# frozen_string_literal: true

module Teams
  # The Teams app a customer's administrator uploads to their organization
  # (docs/design/teams-integration.md §6.3): a manifest naming this deployment's
  # bot, and its two icons, zipped. Built per deployment rather than shipped, so a
  # self-hosted Aixle hands out a package for its own bot.
  module AppPackage
    # Raised whenever the manifest changes, so an organization can tell its
    # installed package is older than the one Aixle offers.
    VERSION = "1.1.0"
    SCHEMA = "1.30"
    COLOR_ICON = Rails.root.join("public/icon-192.png")
    OUTLINE_ICON = Rails.root.join("app/assets/images/teams/outline.png")

    module_function

    def filename = "aixle-flow-teams-#{VERSION}.zip"

    def zip
      Zip.write(
        "manifest.json" => JSON.pretty_generate(manifest),
        "color.png" => File.binread(COLOR_ICON),
        "outline.png" => File.binread(OUTLINE_ICON)
      )
    end

    # The Teams app id must never change once an organization has installed it,
    # so it is derived from the bot's own id rather than configured beside it.
    def manifest_id = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "aixle-flow-teams:#{Config.app_id}")

    def manifest
      app_id = Config.app_id
      base = "#{Settings.protocol}://#{Settings.domain}"
      {
        "$schema" => "https://developer.microsoft.com/json-schemas/teams/v#{SCHEMA}/MicrosoftTeams.schema.json",
        "manifestVersion" => SCHEMA,
        "version" => VERSION,
        "id" => manifest_id,
        "developer" => { "name" => "Aixle", "websiteUrl" => base, "privacyUrl" => "#{base}/privacy-policy",
                         "termsOfUseUrl" => "#{base}/terms-of-service" },
        "name" => { "short" => "Aixle Flow", "full" => "Aixle Flow" },
        "description" => {
          "short" => "Start Aixle Flow workflows from Teams",
          "full" => "Mention Aixle Flow in a channel or chat, or message it directly, to start the workflow your " \
                    "team set up for that request. It answers in the thread. Aixle Flow reads the messages of a " \
                    "conversation it is added to only to find the ones addressed to it and to give a workflow the " \
                    "thread it was started from; other messages are dropped on arrival and never stored."
        },
        "icons" => { "color" => "color.png", "outline" => "outline.png" },
        "accentColor" => "#0A0908",
        "bots" => [ {
          "botId" => app_id,
          "scopes" => %w[personal team groupChat],
          "supportsFiles" => true,
          "isNotificationOnly" => false,
          # `/help` in a channel or group chat is a private message to the bot,
          # answered privately (Teams' targeted messages).
          "supportsTargetedMessages" => true,
          "commandLists" => [ { "scopes" => %w[personal team groupChat], "triggers" => %w[slash mention],
                                "commands" => [ { "title" => "help", "description" => "What this conversation can start" } ] } ]
        } ],
        "webApplicationInfo" => { "id" => app_id, "resource" => "api://#{Settings.domain}/botid-#{app_id}" },
        "authorization" => { "permissions" => { "resourceSpecific" => [
          { "name" => "ChannelMessage.Read.Group", "type" => "Application" },
          { "name" => "ChatMessage.Read.Chat", "type" => "Application" }
        ] } },
        "validDomains" => [ Settings.domain.to_s.split(":").first ]
      }
    end

    # Enough of PKZIP for a few small files: deflated entries, one central
    # directory. Not worth a runtime dependency on a zip library.
    module Zip
      DOS_DATE = ((2026 - 1980) << 9) | (1 << 5) | 1

      module_function

      def write(files)
        body = +"".b
        directory = +"".b
        files.each do |name, content|
          data = content.to_s.b
          packed = deflate(data)
          crc = Zlib.crc32(data)
          sizes = [ crc, packed.bytesize, data.bytesize, name.bytesize ]
          directory << [ 0x02014b50, 20, 20, 0, 8, 0, DOS_DATE, *sizes, 0, 0, 0, 0, 0, body.bytesize ]
                       .pack("VvvvvvvVVVvvvvvVV") << name.b
          body << [ 0x04034b50, 20, 0, 8, 0, DOS_DATE, *sizes, 0 ].pack("VvvvvvVVVvv") << name.b << packed
        end
        body + directory + [ 0x06054b50, 0, 0, files.size, files.size, directory.bytesize, body.bytesize, 0 ].pack("VvvvvVVv")
      end

      def deflate(data)
        stream = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
        stream.deflate(data, Zlib::FINISH).tap { stream.close }
      end
    end
  end
end
