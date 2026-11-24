require "csv"

namespace :monitor do
  desc "Replay the week on a 15-minute clock and write out/alerts.csv + out/alerts.json"
  task run: :environment do
    alerts = HealthMonitor::Runner.call
    cols = %w[detected_at check_name severity partner_id affected_count sample_ids last_new_at resolved_at detail]
    fmt = ->(v) { v.respond_to?(:strftime) ? v.strftime("%F %H:%M") : v }
    out = Rails.root.join("out")
    FileUtils.mkdir_p(out)
    CSV.open(out.join("alerts.csv"), "w") do |csv|
      csv << cols
      alerts.each { |a| csv << cols.map { |c| c == "sample_ids" ? a.sample_ids.join(" ") : fmt.(a[c]) } }
    end
    File.write(out.join("alerts.json"), JSON.pretty_generate(alerts.map { |a| cols.to_h { |c| [c, fmt.(a[c])] } }))
    alerts.each do |a|
      puts format("%-16s %-18s %-8s %-3s n=%-4d %-16s %s", fmt.(a.detected_at), a.check_name, a.severity,
                  a.partner_id, a.ids.size, a.resolved_at ? "→ #{fmt.(a.resolved_at)}" : "open", a.detail)
    end
    puts "#{alerts.size} alerts written to out/alerts.csv and out/alerts.json"

    # Leads still stuck at the end of the data: work to do, not an alert (see Stall).
    backlog = HealthMonitor::Runner.backlog
    CSV.open(out.join("backlog.csv"), "w") do |csv|
      csv << %w[partner_id stuck_before count lead_ids]
      backlog.each { |f| csv << [f.partner_id, f.key.split(":")[1], f.ids.size, f.ids.join(" ")] }
    end
    backlog.each { |f| puts "backlog: #{f.partner_id} #{f.detail}" }
    puts "#{backlog.sum { |f| f.ids.size }} stuck leads written to out/backlog.csv"
  end
end
