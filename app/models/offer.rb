# == Schema Information
#
# Table name: offers
#
#  id         :bigint           not null, primary key
#  currency   :string
#  title      :string
#  type       :string
#  value      :decimal(, )
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_offers_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Offer < ApplicationRecord
  self.inheritance_column = nil

  belongs_to :account
  has_one_attached :image

  validates :title, presence: true
  validates :value, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :type, presence: true

  TYPE_SERVICE = 'service'.freeze
  TYPE_PRODUCT = 'product'.freeze
end
