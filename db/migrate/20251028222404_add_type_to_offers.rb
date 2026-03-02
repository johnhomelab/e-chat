class AddTypeToOffers < ActiveRecord::Migration[7.2]
  def change
    add_column :offers, :type, :string
  end
end
