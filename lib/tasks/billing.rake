require "csv"

namespace :billing do
  desc "Part C: reconcile billing.csv against the data -> out/reconciliation.csv"
  task reconcile: :environment do
    rows = BillingReconciler.call
    FileUtils.mkdir_p(Rails.root.join("out"))
    CSV.open(Rails.root.join("out/reconciliation.csv"), "w") do |csv|
      csv << rows.first.keys
      rows.each { |r| csv << r.values }
    end
    rows.each do |r|
      puts format("%-6s %-3s %-13s billed %-4d supported %-4d diff %+4d %+8s  %-8s %s", r["line_id"], r["partner_id"],
                  r["unit_type"], r["billed_units"], r["supported_units"], r["diff_units"], "$#{r['dollar_impact']}",
                  r["decision"], r["reason"])
    end
    puts "out/reconciliation.csv written"
  end
end
