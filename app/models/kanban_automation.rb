# == Schema Information
#
# Table name: kanban_automations
#
#  id          :bigint           not null, primary key
#  actions     :jsonb
#  active      :boolean          default(TRUE)
#  conditions  :jsonb
#  description :text
#  name        :string
#  trigger     :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_kanban_automations_on_account_id           (account_id)
#  index_kanban_automations_on_account_id_and_name  (account_id,name)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#

class KanbanAutomation < ApplicationRecord
  validates :name, presence: true
  validates :trigger, presence: true
  validates :actions, presence: true

  # Valores padrão para os campos JSON
  after_initialize :set_defaults, if: :new_record?

  private

  def set_defaults
    self.active = true if active.nil?
    self.trigger ||= {}
    self.conditions ||= []
    self.actions ||= []
  end
end
