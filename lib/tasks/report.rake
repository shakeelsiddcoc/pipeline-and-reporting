require "csv"

namespace :report do
  desc "Part B: write the daily funnel report to out/funnel_<section>.csv"
  task funnel: :environment do
    FileUtils.mkdir_p(Rails.root.join("out"))
    FunnelReport.all.each do |section, rows|
      path = Rails.root.join("out/funnel_#{section}.csv")
      CSV.open(path, "w") do |csv|
        csv << rows.first.keys
        rows.each { |r| csv << r.values }
      end
      puts "#{path.relative_path_from(Rails.root)}: #{rows.size} rows"
    end
  end
end
