class CreateSpreeSalesTaxRates < ActiveRecord::Migration[7.1]
  def change
    create_table :spree_sales_tax_rates do |t|
      t.references :country, null: false
      t.references :state, null: false
      t.string :zip_code, null: false
      t.string :name
      t.decimal :rate, precision: 8, scale: 5, null: false
      t.text :preferences

      t.timestamps
    end

    add_index :spree_sales_tax_rates, [:country_id, :state_id, :zip_code], unique: true
  end
end
