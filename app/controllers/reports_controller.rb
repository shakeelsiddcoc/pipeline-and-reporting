# Part B: daily funnel report, one day per page (the "morning report").
class ReportsController < PagesController
  def show
    report = FunnelReport.all
    @days = report.values.flatten.map { |r| r["day"] }.uniq.sort
    @day = @days.include?(params[:day]) ? params[:day] : @days.last
    @sections = report.transform_values { |rows| rows.select { |r| r["day"] == @day } }
    totals = report["leads"].select { |r| r["partner_id"] == "ALL" }.index_by { |r| r["day"] }
    new_alerts = Alert.order(:detected_at).group_by { |a| a.detected_at.to_date.to_s }
    @strip = @days.map do |d|
      { day: d, received: totals[d]&.dig("received"), acceptance: totals[d]&.dig("acceptance_rate"),
        new_alerts: Array(new_alerts[d]).map(&:severity) }
    end
    return unless @day

    @prev_day = @days[@days.index(@day) - 1] if @days.index(@day).positive?
    @prev = report.transform_values { |rows| rows.select { |r| r["day"] == @prev_day } }
    start = Time.utc(*@day.split("-").map(&:to_i))
    @alerts = Alert.where(detected_at: ...start + 1.day)
                   .where("resolved_at IS NULL OR resolved_at >= ?", start).order(:detected_at)
  end
end
