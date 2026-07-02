# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::AlipayService do
  subject(:service) { described_class.new(payment_request) }

  let(:payment_request) { create(:payment_request, customer:, organization:, amount_currency: "CNY") }
  let(:payment_provider) { create(:alipay_provider, code: "alipay", organization:) }
  let(:provider_customer) { create(:alipay_customer, payment_provider:, customer:) }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, payment_provider: "alipay", payment_provider_code: "alipay") }

  describe "#provider_payment_id" do
    it "generates an Alipay-compatible merchant order number" do
      provider_payment_id = service.send(:provider_payment_id)

      expect(provider_payment_id.length).to be <= 64
      expect(provider_payment_id).to match(/\A[a-zA-Z0-9_]+\z/)
    end
  end

  describe "#generate_payment_url" do
    before { provider_customer }

    context "when a pending Alipay payment already exists" do
      before do
        create(
          :payment,
          payable: payment_request,
          payment_provider:,
          payment_provider_customer: provider_customer,
          organization:,
          customer:,
          provider_payment_id: "pr_existing",
          payable_payment_status: "processing"
        )
      end

      it "reuses the existing merchant order number" do
        result = service.generate_payment_url
        session = JSON.parse(Base64.urlsafe_decode64(Rack::Utils.parse_query(URI.parse(result.payment_url).query)["session"]))
        biz_content = JSON.parse(session["fields"]["biz_content"])

        expect(biz_content["out_trade_no"]).to eq("pr_existing")
        expect(session["out_trade_no"]).to eq("pr_existing")
      end
    end
  end

  describe "#update_payment_status" do
    before { provider_customer }

    let!(:payment) do
      create(
        :payment,
        payable: payment_request,
        payment_provider:,
        payment_provider_customer: provider_customer,
        organization:,
        customer:,
        amount_cents: 200_00,
        amount_currency: "CNY",
        provider_payment_id: "pr_existing",
        payable_payment_status: "processing"
      )
    end

    it "rejects the webhook when the Alipay amount does not match the Lago payment amount" do
      result = service.update_payment_status(
        organization_id: organization.id,
        status: "TRADE_SUCCESS",
        alipay_payment: PaymentProviders::AlipayProvider::AlipayPayment.new(
          id: "pr_existing",
          status: "TRADE_SUCCESS",
          amount_cents: 100_00,
          metadata: {}
        )
      )

      expect(result).not_to be_success
      expect(result.error.code).to eq("invalid_payment_amount")
      expect(payment.reload.payable_payment_status).to eq("processing")
      expect(payment_request.reload).to be_payment_pending
    end
  end
end
