# Overview: the week at a glance, built from the same SQL as the daily report and reconciliation.
class DashboardController < PagesController
  def show
    report = FunnelReport.all
    @days = report["leads"].map { |r| r["day"] }.uniq.sort # the reporting week (leads' received dates)
    return if @days.empty?

    @labels = @days.map { |d| Date.parse(d).strftime("%a %-d") }
    ids = ->(type) { Partner.where(partner_type: type).order(:partner_id).pluck(:partner_id) }
    @publishers, @buyers, @intakes = ids.("publisher"), ids.("buyer"), ids.("intake_center")
    @leads, @stages, @deliveries, @calls = report.values_at("leads", "stages", "deliveries", "calls")

    all = ->(rows, col) { @days.map { |d| rows.find { |r| r["day"] == d && r["partner_id"] == "ALL" }&.dig(col).to_i } }
    @received_daily = all.(@leads, "received")
    @accepted_daily = all.(@leads, "accepted")
    @cases_daily = all.(@deliveries, "cases_delivered")
    @billable_daily = all.(@calls, "billable")
    @cases_after_week = @deliveries.select { |r| r["partner_id"] == "ALL" && !@days.include?(r["day"]) }.sum { |r| r["cases_delivered"] }
    @funnel = PipelineRules::STAGES.to_h { |s| [s, @stages.select { |r| r["partner_type"] == "all" }.sum { |r| r[s] }] }
    @funnel_accepted = @stages.select { |r| r["partner_type"] == "all" }.sum { |r| r["accepted"] }
    @alerts = Alert.order(:detected_at)
    @billing = BillingReconciler.call
  end

  helper_method def series(ids, rows, col)
    ids.map do |id|
      { name: "#{id} #{@partners[id]}", slot: helpers.series_slot(id),
        values: @days.map { |d| rows.find { |r| r["day"] == d && r["partner_id"] == id }&.dig(col) } }
    end
  end
end
