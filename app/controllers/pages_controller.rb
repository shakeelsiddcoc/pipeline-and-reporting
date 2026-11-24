# Base for the HTML reporting pages. ApplicationController is the API base, so the layout is set here.
class PagesController < ActionController::Base
  layout "application"
  before_action :load_period

  private

  def load_period
    @partners = Partner.pluck(:partner_id, :name).to_h
    @week_start = Lead.minimum(:received_at)&.beginning_of_day
    @week_end = @week_start && @week_start + 7.days
  end
end
