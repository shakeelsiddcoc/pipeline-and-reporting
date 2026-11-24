# Part A: alerts written by `bin/rails monitor:run`.
class AlertsController < PagesController
  def index
    @alerts = Alert.order(:detected_at)
  end
end
