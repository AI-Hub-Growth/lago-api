# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::AlipayService do
  subject(:alipay_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:provider_attributes) do
    {
      organization:,
      app_id: "2021000000000000",
      app_private_key: "private-key",
      alipay_public_key: "public-key",
      code: "alipay",
      name: "Alipay"
    }
  end

  describe ".create_or_update" do
    it "stores the selected environment on the payment provider" do
      result = alipay_service.create_or_update(**provider_attributes, environment: "sandbox")

      expect(result).to be_success
      expect(result.alipay_provider.environment).to eq("sandbox")
      expect(result.alipay_provider.settings["environment"]).to eq("sandbox")
    end

    it "updates the selected environment" do
      provider = create(:alipay_provider, organization:, code: "alipay", environment: "sandbox")

      result = alipay_service.create_or_update(
        organization:,
        id: provider.id,
        environment: "production"
      )

      expect(result).to be_success
      expect(result.alipay_provider.reload.environment).to eq("production")
    end

    it "rejects an invalid environment" do
      result = alipay_service.create_or_update(**provider_attributes, environment: "invalid")

      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages[:environment]).to eq(["value_is_invalid"])
    end
  end
end
