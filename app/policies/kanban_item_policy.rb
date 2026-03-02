class KanbanItemPolicy < ApplicationPolicy
  def index?
    true
  end

  def filter?
    true
  end

  def reports?
    @account_user.administrator? || @account_user.agent?
  end

  def export?
    @account_user.administrator? || @account_user.agent?
  end

  def import_preview?
    @account_user.administrator? || @account_user.agent?
  end

  def import?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    @account_user.administrator? || @account_user.agent?
  end

  def destroy?
    @account_user.administrator?
  end

  # Métodos auxiliares
  def assigned_to_user?
    record.assigned_agents.any? { |a| a['id'] == @account_user.id }
  end

  def move_to_stage?
    update?
  end

  def reorder?
    update?
  end

  def move?
    update?
  end

  def create_checklist_item?
    update?
  end

  def delete_checklist_item?
    update?
  end

  def toggle_checklist_item?
    update?
  end

  def update_checklist_item?
    update?
  end

  def create_note?
    update?
  end

  def assign_agent?
    update?
  end

  def change_status?
    update?
  end

  def assign_agent_to_checklist_item?
    update?
  end

  def remove_agent_from_checklist_item?
    update?
  end

  def remove_agent?
    update?
  end

  def debug?
    @account_user.administrator?
  end

  def move?
    update?
  end

  def create_checklist_item?
    update?
  end

  def create_note?
    update?
  end

  def get_notes?
    show?
  end

  def delete_note?
    update?
  end

  def update_note?
    update?
  end

  def get_checklist?
    show?
  end

  def assign_agent?
    update?
  end

  def assigned_agents?
    show?
  end

  def change_status?
    update?
  end

  def assign_agent_to_checklist_item?
    update?
  end

  def remove_agent_from_checklist_item?
    update?
  end

  def time_report?
    show?
  end

  def stage_time_breakdown?
    show?
  end

  def duplicate_checklist?
    update?
  end

  def search_checklist?
    show?
  end

  def checklist_progress_by_agent?
    show?
  end

  def counts?
    show?
  end

  def bulk_move_items?
    update?
  end

  def bulk_assign_agent?
    update?
  end

  def bulk_set_priority?
    update?
  end

  class Scope < Scope
    def resolve
      if @account_user.administrator?
        scope.where(account_id: Current.account.id)
      else
        # Agents veem apenas itens em que estão assigned
        scope.where(account_id: Current.account.id).select do |item|
          item.assigned_agents.any? { |a| a['id'] == @account_user.id }
        end
      end
    end
  end
end
