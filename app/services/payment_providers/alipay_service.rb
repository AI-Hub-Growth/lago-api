# frozen_string_literal: true

module PaymentProviders
  class AlipayService < BaseService
    def create_or_update(**args)
      payment_provider_result = PaymentProviders::FindService.call(
        organization_id: args[:organization].id,
        code: args[:code],
        id: args[:id],
        payment_provider_type: "alipay"
      )

      alipay_provider = if payment_provider_result.success?
        payment_provider_result.payment_provider
      else
        PaymentProviders::AlipayProvider.new(
          organization_id: args[:organization].id,
          code: args[:code]
        )
      end

      old_code = alipay_provider.code

      alipay_provider.app_id = args[:app_id] if args.key?(:app_id)
      alipay_provider.app_private_key = args[:app_private_key] if args.key?(:app_private_key)
      alipay_provider.alipay_public_key = args[:alipay_public_key] if args.key?(:alipay_public_key)
      alipay_provider.payment_mode = "checkout"
      alipay_provider.success_redirect_url = args[:success_redirect_url] if args.key?(:success_redirect_url)
      alipay_provider.code = args[:code] if args.key?(:code)
      alipay_provider.name = args[:name] if args.key?(:name)
      alipay_provider.save!

      if payment_provider_code_changed?(alipay_provider, old_code, args)
        alipay_provider.customers.update_all(payment_provider_code: args[:code]) # rubocop:disable Rails/SkipsModelValidations
      end

      result.alipay_provider = alipay_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
