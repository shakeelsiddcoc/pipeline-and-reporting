# Part B: daily funnel report, one day per page (the "morning report").
class ReportsController < PagesController
  def show
    report = FunnelReport.all
    @days = report.values.flatten.map { |r| r["day"] }.uniq.sort
    @day = @days.include?(params[:day]) ? params[:day] : @days.last
    @sections = report.transform_values { |rows| rows.select { |r| r["day"] == @day } }
    return unless @day

    @prev_day = @days[@days.index(@day) - 1] if @days.index(@day).positive?
    @prev = report.transform_values { |rows| rows.select { |r| r["day"] == @prev_day } }
    start = Time.utc(*@day.split("-").map(&:to_i))
    @alerts = Alert.where(detected_at: ...start + 1.day)
                   .where("resolved_at IS NULL OR resolved_at >= ?", start).order(:detected_at)
  end
end
