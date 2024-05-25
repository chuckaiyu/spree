class CreateSpreePaypalCheckoutOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :spree_paypal_checkout_orders do |t|
      t.references :payment_method
      t.references :user
      t.string :order_id
      t.string :intent
      t.string :status
      t.string :capture_id
      t.string :capture_status
      t.string :authorization_id
      t.string :authorization_status
      t.string :authentication_expiration_time
      t.jsonb :refunds
      t.text :preferences
      t.timestamps
    end
  end
end
