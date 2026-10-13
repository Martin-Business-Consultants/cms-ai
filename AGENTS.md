# AI, a Libre Publish plugin — guide for AI agents

A Rails engine loaded into a CMS install from `plugins/ai`. Read the core's `docs/plugins.md` and
`STYLE.md` first.

- `Ai.structured` is the one way a plugin asks a model; `Ai.available?` and `Ai.unavailable_reason`
  say whether it can. Other plugins check `defined?(::Ai)` first and work without it.
- `Ai::Settings` lives in the core's Setting "ai", the key among its secrets (never rendered or read
  back). `Ai::Settings#protocol_for` picks the endpoint a model is served on following OpenCode's documented tables
  (opencode.ai/v2/docs/console/models and /console/go); a model it can't use (Jev) answers nil.
- `Ai::Client` speaks each protocol over Net::HTTP (a plugin may use only the gems the core bundles),
  records every request in `Ai::Request`, retries what may pass, and takes an injectable transport
  for specs.

Check: `bin/rspec plugins/ai/spec`, `bin/rubocop plugins/ai`, `bundle exec herb lint plugins/ai/app/views`.
