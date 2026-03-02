class AddAccountToOffers < ActiveRecord::Migration[7.2]
  def change
    add_reference :offers, :account, null: false, foreign_key: true
  end
end
