# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Alipay::Customers::CreateService do
  subject(:service) do
    described_class.new(
      customer:,
      payment_provider_id: alipay_provider.id,
      params:,
      async: false
    )
  end

  let(:organization) { create(:organization, feature_flags: %w[multiple_payment_methods]) }
  let(:customer) { create(:customer, organization:, payment_provider: "alipay", payment_provider_code: alipay_provider.code) }
  let(:alipay_provider) { create(:alipay_provider, organization:) }
  let(:params) { {sync_with_provider: true} }

  describe "#call" do
    it "creates an Alipay provider customer without an external provider customer id" do
      result = service.call

      expect(result).to be_success
      expect(result.provider_customer).to be_a(PaymentProviderCustomers::AlipayCustomer)
      expect(result.provider_customer.provider_customer_id).to be_nil
      expect(result.provider_customer.payment_provider).to eq(alipay_provider)
    end

    it "creates a default Alipay payment method for invoice payment method selection" do
      expect { service.call }.to change(PaymentMethod, :count).by(1)

      payment_method = customer.payment_methods.sole
      expect(payment_method.is_default).to be(true)
      expect(payment_method.payment_provider).to eq(alipay_provider)
      expect(payment_method.payment_provider_customer).to eq(customer.alipay_customer)
      expect(payment_method.provider_method_id).to eq("alipay")
      expect(payment_method.provider_method_type).to eq("alipay")
      expect(payment_method.details).to eq({"type" => "alipay"})
    end

    it "makes the Alipay payment method available through the customer payment methods query" do
      service.call

      result = PaymentMethodsQuery.call(
        organization:,
        filters: {external_customer_id: customer.external_id, with_deleted: false}
      )

      expect(result.payment_methods.sole.provider_method_type).to eq("alipay")
    end

    context "when the Alipay provider customer already exists" do
      let!(:provider_customer) { create(:alipay_customer, customer:, organization:, payment_provider: old_alipay_provider) }
      let(:old_alipay_provider) { create(:alipay_provider, organization:) }
      let!(:payment_method) do
        create(
          :payment_method,
          customer:,
          organization:,
          payment_provider: old_alipay_provider,
          payment_provider_customer: provider_customer,
          provider_method_id: "alipay",
          provider_method_type: "alipay",
          is_default: false,
          details: {type: "alipay"}
        )
      end

      it "reuses the existing records and updates them to the selected Alipay provider" do
        expect { service.call }.not_to change(PaymentMethod, :count)

        expect(provider_customer.reload.payment_provider).to eq(alipay_provider)
        expect(payment_method.reload.payment_provider).to eq(alipay_provider)
        expect(payment_method.is_default).to be(true)
      end
    end
  end
end
