# == Schema Information
#
# Table name: funnels
#
#  id                       :bigint           not null, primary key
#  active                   :boolean          default(TRUE)
#  description              :string
#  global_custom_attributes :jsonb            not null
#  name                     :string           not null
#  settings                 :jsonb
#  stages                   :jsonb            not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#
# Indexes
#
#  index_funnels_on_account_id           (account_id)
#  index_funnels_on_account_id_and_name  (account_id,name) UNIQUE
#

class Funnel < ApplicationRecord
  include Events::Types

  belongs_to :account
  has_many :kanban_items, dependent: :delete_all

  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id }
  validates :stages, presence: true
  validate :validate_stages_format

  scope :active, -> { where(active: true) }
  scope :ordered_by_name, -> { order(:name) }

  def available_stages
    stages.keys
  end

  def stage_settings(stage_name)
    stages[stage_name] || {}
  end

  # Garante que global_custom_attributes sempre seja um array
  def global_custom_attributes
    value = self[:global_custom_attributes]
    value.is_a?(Array) ? value : []
  end

  def global_custom_attributes=(value)
    self[:global_custom_attributes] = value.is_a?(Array) ? value : []
  end

  validate :validate_global_custom_attributes_format

  private

  def validate_stages_format
    return if stages.blank?
    return if stages.is_a?(Hash)

    errors.add(:stages, 'deve ser um objeto JSON válido')
  end

  def validate_global_custom_attributes_format
    return if global_custom_attributes.blank?
    unless global_custom_attributes.is_a?(Array) && global_custom_attributes.all? { |attr| attr.is_a?(Hash) && attr['name'].present? && attr['type'].present? }
      errors.add(:global_custom_attributes, 'deve ser um array de hashes com name e type')
    end
  end
end 
