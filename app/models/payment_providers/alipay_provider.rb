# frozen_string_literal: true

module PaymentProviders
  class AlipayProvider < BaseProvider
    AlipayPayment = Data.define(:id, :status, :metadata, :amount_cents)

    SUCCESS_REDIRECT_URL = "https://www.alipay.com/"
    ENVIRONMENTS = %w[sandbox production].freeze
    PAYMENT_MODES = %w[checkout].freeze

    PROCESSING_STATUSES = %w[WAIT_BUYER_PAY].freeze
    SUCCESS_STATUSES = %w[TRADE_SUCCESS TRADE_FINISHED].freeze
    FAILED_STATUSES = %w[TRADE_CLOSED].freeze

    validates :app_id, presence: true
    validates :app_private_key, presence: true
    validates :alipay_public_key, presence: true
    validates :environment, inclusion: {in: ENVIRONMENTS}
    validates :payment_mode, inclusion: {in: PAYMENT_MODES}
    validates :success_redirect_url, url: true, allow_nil: true, length: {maximum: 1024}

    secrets_accessors :app_id, :app_private_key, :alipay_public_key
    settings_accessors :environment, :payment_mode

    def payment_type
      "alipay"
    end

    def environment
      get_from_settings("environment").presence || legacy_environment || default_environment
    end

    def payment_mode
      mode = get_from_settings("payment_mode").presence

      PAYMENT_MODES.include?(mode) ? mode : "checkout"
    end

    def checkout_payment_url(payment_intent)
      URI.join(
        ENV["LAGO_API_URL"],
        "payment_providers/alipay/checkouts/#{payment_intent.id}"
      ).to_s
    end

    def checkout_session_payment_url(session)
      encoded_session = Base64.urlsafe_encode64(JSON.generate(session))

      "#{URI.join(ENV["LAGO_API_URL"], "payment_providers/alipay/checkouts")}?session=#{encoded_session}"
    end

    private

    def legacy_environment
      ENV["LAGO_ALIPAY_ENVIRONMENT"].to_s.downcase.presence_in(ENVIRONMENTS)
    end

    def default_environment
      Rails.env.production? ? "production" : "sandbox"
    end
  end
end

# == Schema Information
#
# Table name: payment_providers
# Database name: primary
#
#  id              :uuid             not null, primary key
#  code            :string           not null
#  deleted_at      :datetime
#  name            :string           not null
#  secrets         :string
#  settings        :jsonb            not null
#  type            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
