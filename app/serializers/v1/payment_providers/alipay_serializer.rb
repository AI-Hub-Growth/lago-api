# frozen_string_literal: true

module V1
  module PaymentProviders
    class AlipaySerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          code: model.code,
          name: model.name,
          payment_provider: model.payment_type,
          success_redirect_url: model.success_redirect_url,
          created_at: model.created_at.iso8601
        }
      end
    end
  end
end
