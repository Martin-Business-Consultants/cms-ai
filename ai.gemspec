# frozen_string_literal: true

require_relative "lib/ai/version"

Gem::Specification.new do |spec|
  spec.name = "ai"
  spec.version = Ai::VERSION
  spec.summary = "AI for Libre Publish: one provider (OpenCode Zen, Anthropic, OpenAI, OpenRouter or your own Ollama) that every plugin asks"
  spec.authors = ["Martin Business Consultants"]
  spec.license = "FSL-1.1-MIT"
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
end
