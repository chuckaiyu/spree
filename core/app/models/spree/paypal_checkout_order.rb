module Spree
  class PaypalCheckoutOrder < Spree::Base
    attribute :refunds, default: []

    attr_accessor :imported

    belongs_to :payment_method
    belongs_to :user, class_name: Spree.user_class.to_s, foreign_key: 'user_id', optional: true
    has_many :payments, as: :source

    validates_presence_of :order_id

    def authentication_expiration_at
      DateTime.parse(authentication_expiration_time)  if authentication_expiration_time.present?
    end

    def actions
      %w[capture void credit]
    end

    def can_capture?(payment)
      payment.pending? || payment.checkout?
    end

    def can_void?(payment)
      !payment.failed? && !payment.void? && can_void_authorized?
    end

    def can_credit?(payment)
      payment.completed? && payment.credit_allowed > 0
    end

    private

    def can_void_authorized?
      authorization_id.present? && authorization_status.present? && authorization_status != "COMPLETED"
    end
  end
end
