# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::AlipayService do
  subject(:service) { described_class.new(invoice) }

  let(:payment_provider) { create(:alipay_provider, code: "alipay", organization:) }
  let(:provider_customer) { create(:alipay_customer, payment_provider:, customer:) }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, payment_provider: "alipay", payment_provider_code: "alipay") }
  let(:invoice) { create(:invoice, customer:, organization:, currency: "CNY") }

  describe "#provider_payment_id" do
    it "generates an Alipay-compatible merchant order number" do
      provider_payment_id = service.send(:provider_payment_id, "invoice", invoice.id)

      expect(provider_payment_id.length).to be <= 64
      expect(provider_payment_id).to match(/\A[a-zA-Z0-9_]+\z/)
    end
  end

  describe "#generate_payment_url" do
    let(:payment_intent) { create(:payment_intent, invoice:, organization:) }

    before { provider_customer }

    it "returns a Lago checkout URL that renders the Alipay POST form" do
      result = service.generate_payment_url(payment_intent)
      session = JSON.parse(result.provider_session_id)

      expect(URI.parse(result.payment_url).path).to eq(
        "/payment_providers/alipay/checkouts/#{payment_intent.id}"
      )
      expect(session["gateway_url"]).to eq("#{PaymentProviders::Alipay::Client::SANDBOX_GATEWAY_URL}?charset=utf-8")
      expect(session["fields"]["method"]).to eq("alipay.trade.page.pay")
      expect(session["fields"]["sign"]).to be_present
    end

    context "when a pending Alipay payment already exists" do
      before do
        create(
          :payment,
          payable: invoice,
          payment_provider:,
          payment_provider_customer: provider_customer,
          organization:,
          customer:,
          provider_payment_id: "inv_existing",
          payable_payment_status: "processing"
        )
      end

      it "reuses the existing merchant order number" do
        result = service.generate_payment_url(payment_intent)
        session = JSON.parse(result.provider_session_id)
        biz_content = JSON.parse(session["fields"]["biz_content"])

        expect(biz_content["out_trade_no"]).to eq("inv_existing")
        expect(session["out_trade_no"]).to eq("inv_existing")
      end
    end
  end

  describe "#expire_payment_url" do
    let(:payment_intent) { create(:payment_intent, invoice:, organization:, provider_session_id: "{\"out_trade_no\":\"inv_existing\"}") }

    before { provider_customer }

    it "treats the local checkout session expiration as a no-op success" do
      result = service.expire_payment_url(payment_intent)

      expect(result).to be_success
    end
  end

  describe "#update_payment_status" do
    before { provider_customer }

    let!(:payment) do
      create(
        :payment,
        payable: invoice,
        payment_provider:,
        payment_provider_customer: provider_customer,
        organization:,
        customer:,
        amount_cents: 200_00,
        amount_currency: "CNY",
        provider_payment_id: "inv_existing",
        payable_payment_status: "processing"
      )
    end

    it "rejects the webhook when the Alipay amount does not match the Lago payment amount" do
      result = service.update_payment_status(
        organization_id: organization.id,
        status: "TRADE_SUCCESS",
        alipay_payment: PaymentProviders::AlipayProvider::AlipayPayment.new(
          id: "inv_existing",
          status: "TRADE_SUCCESS",
          amount_cents: 100_00,
          metadata: {}
        )
      )

      expect(result).not_to be_success
      expect(result.error.code).to eq("invalid_payment_amount")
      expect(payment.reload.payable_payment_status).to eq("processing")
      expect(invoice.reload).to be_payment_pending
    end
  end
end
