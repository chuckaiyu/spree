module Spree
  class Gateway::PaypalCheckout < Gateway
    preference :paypal_client_id, :string
    preference :paypal_client_secret, :string

    def method_type
      "paypal_checkout"
    end

    def provider_class
      self.class
    end

    def client
      if preferred_test_mode
        environment = PayPal::SandboxEnvironment.new(preferred_paypal_client_id, preferred_paypal_client_secret)
      else
        environment = PayPal::LiveEnvironment.new(preferred_paypal_client_id, preferred_paypal_client_secret)
      end

      @client ||= PayPal::PayPalHttpClient.new(environment)
    end

    def intent
      auto_capture? ? "CAPTURE" : "AUTHORIZE"
    end

    def authorize(amount_in_cents, paypal_checkout_order, gateway_options = {})
      request = PayPalCheckoutSdk::Orders::OrdersAuthorizeRequest::new(paypal_checkout_order.order_id)

      begin
        response = client.execute(request)
        order = response.result

        if order.status == "COMPLETED"
          authorization_id = order.purchase_units.first&.payments&.authorizations&.first&.id
          authorization_status = order.purchase_units.first&.payments&.authorizations&.first&.status
          expiration_time = order.purchase_units.first&.payments&.authorizations&.first&.expiration_time
          paypal_checkout_order.update(status: order.status, authorization_id: authorization_id, authorization_status: authorization_status, authentication_expiration_time: expiration_time)

          ActiveMerchant::Billing::Response.new(true, "Authorize completed", {}, id: order.id, status: order.status, authorization: authorization_id)
        else
          ActiveMerchant::Billing::Response.new(false, "Authorize #{order.status.downcase}", {}, id: order.id, status: order.status)
        end
      rescue PayPalHttp::HttpError => ioe
        ActiveMerchant::Billing::Response.new(false, "Authorize http error", {}, debug_id: ioe.headers["paypal-debug-id"], status: ioe.status_code)
      end
    end

    def purchase(amount_in_cents, paypal_checkout_order, gateway_options = {})
      request = PayPalCheckoutSdk::Orders::OrdersCaptureRequest::new(paypal_checkout_order.order_id)

      begin
        response = client.execute(request)
        order = response.result

        if order.status == "COMPLETED"
          capture_id = order.purchase_units.first&.payments&.captures&.first&.id
          capture_status = order.purchase_units.first&.payments&.captures&.first&.status
          paypal_checkout_order.update(status: order.status, capture_id: capture_id, capture_status: capture_status)

          ActiveMerchant::Billing::Response.new(true, "Purchase completed", {}, id: order.id, status: order.status, authorization: capture_id)
        else
          ActiveMerchant::Billing::Response.new(false, "Purchase #{order.status.downcase}", {}, id: order.id, status: order.status)
        end
      rescue PayPalHttp::HttpError => ioe
        ActiveMerchant::Billing::Response.new(false, "Purchase http error", {}, debug_id: ioe.headers["paypal-debug-id"], status: ioe.status_code)
      end
    end

    def credit(amount_in_cents, response_code, gateway_options = {})
      currency_code = gateway_options[:originator].money.currency.iso_code
      if currency_code == 'USD'
        amount = (amount_in_cents * 0.01).round(2)
      end

      request = PayPalCheckoutSdk::Payments::CapturesRefundRequest::new(response_code)
      request.request_body({
        amount: {
          value: amount,
          currency_code: currency_code
        },
        note_to_payer: gateway_options[:originator]&.reason&.name
      })

      begin
        response = client.execute(request)
        payment = response.result

        if payment.status == "COMPLETED"
          paypal_checkout_order = PaypalCheckoutOrder.find_by_capture_id(response_code)
          paypal_checkout_order.refunds << { refund_id: payment.id, refund_status: payment.status }
          paypal_checkout_order.save

          ActiveMerchant::Billing::Response.new(true, "Refund completed", {}, authorization: payment.id)
        else
          ActiveMerchant::Billing::Response.new(false, "Refund #{payment.status.downcase}")
        end
      rescue PayPalHttp::HttpError => ioe
        ActiveMerchant::Billing::Response.new(false, "Refund http error", {}, debug_id: ioe.headers["paypal-debug-id"], status: ioe.status_code)
      end
    end

    def capture(amount_in_cents, response_code, gateway_options = {})
      paypal_checkout_order = PaypalCheckoutOrder.find_by_authorization_id(response_code)

      if paypal_checkout_order.authentication_expiration_at && Time.now > paypal_checkout_order.authentication_expiration_at
        return ActiveMerchant::Billing::Response.new(false, "Capture authentication expired", {})
      elsif Time.now > paypal_checkout_order.created_at.next_day(3)
        reauthorize_request = PayPalCheckoutSdk::Payments::AuthorizationsReauthorizeRequest::new(response_code)

        begin
          reauthorize_response = client.execute(reauthorize_request)
          reauthorize_payment = reauthorize_response.result
  
          if reauthorize_payment.status == "CREATED"
            response_code = reauthorize_payment.id
          else
            return ActiveMerchant::Billing::Response.new(false, "Capture reauthorize #{reauthorize_payment.status.downcase}")
          end
        rescue PayPalHttp::HttpError => ioe
          return ActiveMerchant::Billing::Response.new(false, "Capture reauthorize http error", {}, debug_id: ioe.headers["paypal-debug-id"], status: ioe.status_code)
        end
      end

      request = PayPalCheckoutSdk::Payments::AuthorizationsCaptureRequest::new(response_code)

      begin
        response = client.execute(request)
        payment = response.result

        if payment.status == "COMPLETED"
          paypal_checkout_order.update(authorization_status: payment.status, capture_id: payment.id, capture_status: payment.status)
          
          ActiveMerchant::Billing::Response.new(true, "Capture completed", {}, id: payment.id, status: payment.status, authorization: payment.id)
        else
          ActiveMerchant::Billing::Response.new(false, "Capture #{payment.status.downcase}", {}, id: payment.id, status: payment.status)
        end
      rescue PayPalHttp::HttpError => ioe
        ActiveMerchant::Billing::Response.new(false, "Capture http error", {}, debug_id: ioe.headers["paypal-debug-id"], status: ioe.status_code)
      end
    end

    def void(response_code, gateway_options = {})
      request = PayPalCheckoutSdk::Payments::AuthorizationsVoidRequest::new(response_code)

      begin
        response = client.execute(request)

        if response.status_code == 204
          paypal_checkout_order = PaypalCheckoutOrder.find_by_authorization_id(response_code)
          paypal_checkout_order.update(authorization_status: 'VOIDED')

          ActiveMerchant::Billing::Response.new(true, "Void completed", {}, authorization: response_code)
        else
          ActiveMerchant::Billing::Response.new(false, "Void #{response.status_code}")
        end
      rescue PayPalHttp::HttpError => ioe
        ActiveMerchant::Billing::Response.new(false, "Void http error", {}, debug_id: ioe.headers["paypal-debug-id"], status: ioe.status_code)
      end
    end

    def cancel(response_code, payment = nil)
      if payment.credit_allowed > 0
        payment.refunds.create(amount: payment.credit_allowed, reason: RefundReason.return_processing_reason)
      end
        
      ActiveMerchant::Billing::Response.new(true, 'Payment all refunded', {})
    end

    def payment_profiles_supported?
      false
    end

    def payment_source_class
      PaypalCheckoutOrder
    end
  end
end
