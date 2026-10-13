# AI

A plugin for the CMS (see `docs/plugins.md` in [Libre Publish](https://github.com/Martin-Business-Consultants/libre-publish)).

One AI provider for every plugin that wants one: Market's plans, Leads' reply drafts. It's set up once
in **Settings › AI**:

- **OpenCode Zen**: Claude, GPT, Gemini and the open models (DeepSeek, GLM, Kimi…) on one key.
- **Anthropic**, **OpenAI** or **OpenRouter**.
- **An Ollama server of your own**, where nothing leaves it.

The settings take the key, the model (and a faster one for small jobs), a list of the provider's
models to pick from, and an optional monthly token limit. *Check the connection* asks the model for a
tiny answer, which proves the key, the model and its endpoint work together. Every request is
recorded with the tokens it took. The key is encrypted with the CMS's secrets and never shown or read
back.

With OpenCode Zen, each model family is reached on the endpoint it's served on:
- Claude (and Qwen) through Anthropic Messages, the answer's shape given as a tool;
- GPT through OpenAI Responses, with a strict JSON schema;
- Gemini through Google's generateContent;
- the open models through chat completions, with a JSON schema, or a JSON object for a model that
  won't take one.

What may pass (the network, 429s, 5xx) is retried with backoff.

## For plugins

    if defined?(Ai) && Ai.available?
      answer = Ai.structured(purpose: "market_plan", system: "…", prompt: "…", schema: {type: "object", …}, user: Current.user)
    else
      Ai.unavailable_reason  # in words, for a person
    end

`Ai.structured` answers a Hash in the schema's shape. It raises `Ai::Unavailable` when the plugin is
off, unset or over its limit, and `Ai::Error` when the provider fails. Call it from a job, since a
model can take a minute.

`GET|PATCH /api/ai/settings` and `GET /api/ai/requests` are listed in `/api/manifest`.

Install it into a CMS checkout (core 1.32 or newer):

    bin/rails "plugins:install[https://github.com/Martin-Business-Consultants/cms-ai]"

or add it from Settings › Plugins, switch it on, and set it up in Settings › AI. Its specs run inside
the CMS, with the plugin in `plugins/ai`:

    bin/rspec plugins/ai/spec

To release, bump `lib/ai/version.rb`, commit, and tag `vX.Y.Z`.
