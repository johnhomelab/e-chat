class KanbanConfigPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    @account_user.administrator?
  end

  def update?
    true
  end

  def destroy?
    @account_user.administrator?
  end

  def test_webhook?
    @account_user.administrator?
  end
end
