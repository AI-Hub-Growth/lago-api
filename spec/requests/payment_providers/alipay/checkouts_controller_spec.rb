# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Alipay::CheckoutsController do
  describe "GET /payment_providers/alipay/checkouts/:id" do
    let(:payment_intent) do
      create(
        :payment_intent,
        provider_session_id: {
          gateway_url: PaymentProviders::Alipay::Client::SANDBOX_GATEWAY_URL,
          fields: {
            charset: "utf-8",
            method: "alipay.trade.page.pay",
            sign_type: "RSA2",
            sign: "signature"
          }
        }.to_json
      )
    end

    it "renders an auto-submitting POST form" do
      get "/payment_providers/alipay/checkouts/#{payment_intent.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("method=\"post\"")
      expect(response.body).to include("#{PaymentProviders::Alipay::Client::SANDBOX_GATEWAY_URL}?charset=utf-8")
      expect(response.body).not_to include("name=\"charset\"")
      expect(response.body).to include("name=\"method\"")
      expect(response.body).to include("value=\"alipay.trade.page.pay\"")
      expect(response.body).to include("submit()")
      expect(response.body).to include("正在前往支付宝收银台")
      expect(response.body).to include("继续支付")
    end

    context "when the payment intent is not found" do
      it "returns not found" do
        get "/payment_providers/alipay/checkouts/#{SecureRandom.uuid}"

        expect(response).to be_not_found_error("alipay_checkout")
      end
    end
  end
end
