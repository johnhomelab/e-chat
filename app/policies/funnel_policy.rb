class FunnelPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def stage_stats?
    show?
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  class Scope < Scope
    def resolve
      scope.where(account_id: Current.account.id)
    end
  end
end
