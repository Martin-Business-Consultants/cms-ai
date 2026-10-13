# frozen_string_literal: true

module Ai
  # A CMS plugin (docs/plugins.md): it extends the core only through
  # Cms::Plugins, and the core never names it. Other plugins ask it through
  # Ai.structured, checking Ai.available? first, and work without it.
  class Engine < ::Rails::Engine
    initializer "ai.migrations" do |app|
      config.paths["db/migrate"].expanded.each { |path| app.config.paths["db/migrate"] << path }
    end

    initializer "ai.routes" do |app|
      app.routes.append do
        admin = proc do
          scope "settings", as: "settings" do
            resource :ai, only: [:show, :update], controller: "ai/settings" do
              resource :check, only: :create, controller: "ai/checks"
              resource :models, only: :create, controller: "ai/models"
            end
          end
        end
        defined?(Cms::PATH) ? scope(path: Cms::PATH, &admin) : admin.call

        scope "api", defaults: {format: :json} do
          scope "ai", module: "ai/api", as: "api_ai" do
            resource :settings, only: [:show, :update]
            resources :requests, only: :index
          end
        end
      end
    end

    config.to_prepare do
      Cms::Plugins.register :ai, name: "AI", version: Ai::VERSION, author: "Martin Business Consultants",
        enabled_by_default: false, requires: ">= 1.32", homepage: "https://github.com/Martin-Business-Consultants/cms-ai",
        description: "One AI provider for every plugin that wants one (Market's plans, Leads' reply drafts): OpenCode, " \
                     "OpenCode Go, Anthropic, OpenAI, OpenRouter or your own Ollama, with its key set once and a monthly token limit."

      Cms::Plugins.settings :ai, "AI", -> { settings_ai_path },
        description: "The provider, its key and model that plugins use, and how many tokens a month they may.",
        capability: "settings:read"

      Cms::Plugins.api :ai, "/api/ai/settings",
        description: "Settings › AI: provider, model, token limit and use this month (read with settings:read, change with settings:write; the key is never read back)."
      Cms::Plugins.api :ai, "/api/ai/requests", description: "The latest requests to the AI provider: who asked, the model, tokens, how each ended."
    end
  end
end
