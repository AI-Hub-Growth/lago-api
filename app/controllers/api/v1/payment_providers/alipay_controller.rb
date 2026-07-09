# frozen_string_literal: true

module Api
  module V1
    module PaymentProviders
      class AlipayController < Api::BaseController
        def update
          result = ::PaymentProviders::AlipayService
            .new(nil)
            .create_or_update(
              **input_params.to_h.symbolize_keys.merge(
                code: params[:code],
                organization: current_organization
              )
            )

          if result.success?
            render_payment_provider(result.alipay_provider)
          else
            render_error_response(result)
          end
        end

        private

        def input_params
          params.require(:payment_provider).permit(
            :name,
            :app_id,
            :app_private_key,
            :alipay_public_key,
            :success_redirect_url
          )
        end

        def render_payment_provider(payment_provider)
          render(
            json: ::V1::PaymentProviders::AlipaySerializer.new(
              payment_provider,
              root_name: "payment_provider"
            )
          )
        end

        def resource_name
          "payment_provider"
        end
      end
    end
  end
end
