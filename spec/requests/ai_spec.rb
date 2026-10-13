# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings › AI", type: :request do
  let(:admin) { create(:user) }

  before do
    switch_plugin :ai, on: true
    sign_in_as admin
    allow_any_instance_of(Ai::Client).to receive(:models).and_return(%w[claude-sonnet-5-5 gpt-5.6-sol jev-1.13 kimi-k3])
  end

  it "is a 404 while the plugin is off" do
    switch_plugin :ai, on: false
    get settings_ai_path
    expect(response).to have_http_status(:not_found)
  end

  it "saves the provider and key, never shows the key again, and keeps it when left blank" do
    get settings_ai_path
    expect(response).to have_http_status(:ok)

    patch settings_ai_path, params: {ai: {provider: "opencode", api_key: "zen-secret", model: "kimi-k3", monthly_token_limit: "5"}}
    expect(Ai::Settings.current).to have_attributes(provider: "opencode", api_key: "zen-secret", model: "kimi-k3", monthly_token_limit: 5.0)

    get settings_ai_path
    expect(response.body).to include("kimi-k3 through OpenCode")
    expect(Ai::Settings.current.model_list).to eq(%w[claude-sonnet-5-5 gpt-5.6-sol jev-1.13 kimi-k3])
    expect(response.body).to include(%(<option selected="selected" value="kimi-k3">kimi-k3</option>), %(<optgroup label="GPT">))
    expect(response.body).not_to include(%(value="jev-1.13"))
    expect(response.body).not_to include("zen-secret")
    patch settings_ai_path, params: {ai: {api_key: ""}}
    expect(Ai::Settings.current.api_key).to eq("zen-secret")
  end

  it "checks the connection and loads the models" do
    Ai::Settings.update("provider" => "opencode", "api_key" => "zen-secret")
    allow_any_instance_of(Ai::Client).to receive(:structured).and_return("ok" => true)

    post settings_ai_check_path
    expect(flash[:notice]).to eq("claude-sonnet-5-5 answered through OpenCode")
    post settings_ai_models_path
    expect(Ai::Settings.current.model_list).to include("kimi-k3")
  end

  it "reads and changes the settings over the API, without the key" do
    headers = {"Authorization" => "Bearer #{admin.api_token!.token}", "Accept" => "application/json"}
    patch "/api/ai/settings", params: {settings: {provider: "opencode", api_key: "zen-secret"}}, headers: headers, as: :json
    expect(response.parsed_body).to include("provider" => "opencode", "key_set" => true)
    expect(response.body).not_to include("zen-secret")

    get "/api/ai/requests", headers: headers
    expect(response.parsed_body["requests"]).to eq([])
  end
end
