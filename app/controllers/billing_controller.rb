# Part C: reconciliation table, computed live from the data.
class BillingController < PagesController
  def show
    @rows = BillingReconciler.call
  end
end
