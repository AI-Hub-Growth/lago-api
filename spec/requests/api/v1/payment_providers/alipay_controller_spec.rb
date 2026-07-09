# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::PaymentProviders::AlipayController do
  let(:organization) { create(:organization) }

  describe "PUT /api/v1/payment_providers/alipay/:code" do
    subject do
      put_with_token(
        organization,
        "/api/v1/payment_providers/alipay/#{provider_code}",
        {payment_provider: upsert_params}
      )
    end

    let(:provider_code) { "alipay_cn" }
    let(:upsert_params) do
      {
        name: "Alipay CN",
        app_id: "2021000000000000",
        app_private_key: "private-key",
        alipay_public_key: "public-key",
        success_redirect_url: "https://example.com/payment-success"
      }
    end

    include_context "with mocked security logger"
    include_examples "requires API permission", "payment_provider", "write"

    it "creates an Alipay payment provider" do
      expect { subject }.to change(PaymentProviders::AlipayProvider, :count).by(1)

      payment_provider = PaymentProviders::AlipayProvider.last

      expect(response).to have_http_status(:success)
      expect(json[:payment_provider]).to include(
        lago_id: payment_provider.id,
        code: provider_code,
        name: upsert_params[:name],
        payment_provider: "alipay",
        success_redirect_url: upsert_params[:success_redirect_url]
      )
      expect(json[:payment_provider]).not_to have_key(:app_private_key)
      expect(json[:payment_provider]).not_to have_key(:alipay_public_key)
      expect(json[:payment_provider]).not_to have_key(:app_id)

      expect(payment_provider.organization).to eq(organization)
      expect(payment_provider.app_id).to eq(upsert_params[:app_id])
      expect(payment_provider.app_private_key).to eq(upsert_params[:app_private_key])
      expect(payment_provider.alipay_public_key).to eq(upsert_params[:alipay_public_key])
    end

    context "when an Alipay payment provider already exists with the same code" do
      let!(:payment_provider) do
        create(
          :alipay_provider,
          organization: organization,
          code: provider_code,
          name: "Old Alipay",
          app_id: "old-app-id",
          app_private_key: "old-private-key",
          alipay_public_key: "old-public-key"
        )
      end

      it "updates the existing provider" do
        expect { subject }.not_to change(PaymentProviders::AlipayProvider, :count)

        expect(response).to have_http_status(:success)
        expect(json[:payment_provider]).to include(
          lago_id: payment_provider.id,
          code: provider_code,
          name: upsert_params[:name],
          payment_provider: "alipay"
        )

        expect(payment_provider.reload.app_id).to eq(upsert_params[:app_id])
        expect(payment_provider.app_private_key).to eq(upsert_params[:app_private_key])
        expect(payment_provider.alipay_public_key).to eq(upsert_params[:alipay_public_key])
      end
    end

    context "when another organization has an Alipay payment provider with the same code" do
      before do
        create(:alipay_provider, organization: create(:organization), code: provider_code)
      end

      it "creates the provider in the API key organization" do
        expect { subject }.to change {
          organization.payment_providers.where(code: provider_code).count
        }.by(1)

        expect(response).to have_http_status(:success)
      end
    end

    context "when required parameters are missing" do
      let(:upsert_params) { {name: "Alipay CN"} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to include(
          app_id: ["value_is_mandatory"],
          app_private_key: ["value_is_mandatory"],
          alipay_public_key: ["value_is_mandatory"]
        )
      end
    end
  end
end
