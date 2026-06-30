# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoUtils::License do
  subject(:license) { described_class.new(url) }

  let(:url) { "https://license.lago" }

  before do
    ENV["LAGO_LICENSE"] = "test-license"
  end

  describe "#verify" do
    context "when license is valid" do
      let(:response) do
        {
          "valid" => true
        }.to_json
      end

      before do
        stub_request(:get, "#{url}/verify/test-license")
          .to_return(body: response, status: 200)
      end

      it "sets premium to true" do
        license.verify

        expect(license).to be_premium
      end
    end

    context "when license is not present" do
      before do
        ENV["LAGO_LICENSE"] = nil
      end

      it "keeps premium to false" do
        license.verify

        expect(license).not_to be_premium
      end
    end

    context "when license is invalid" do
      let(:response) do
        {
          "valid" => false
        }.to_json
      end

      before do
        stub_request(:get, "#{url}/verify/test-license")
          .to_return(body: response, status: 200)
      end

      it "keeps premium to false" do
        license.verify

        expect(license).not_to be_premium
      end
    end
  end

  describe "#premium?" do
    around do |example|
      old_value = ENV["LAGO_UNLOCK_PREMIUM_FEATURES"]
      example.run
    ensure
      ENV["LAGO_UNLOCK_PREMIUM_FEATURES"] = old_value
    end

    context "when premium features are unlocked locally" do
      before do
        ENV["LAGO_UNLOCK_PREMIUM_FEATURES"] = "true"
      end

      it "returns true" do
        expect(license).to be_premium
      end
    end
  end
end
