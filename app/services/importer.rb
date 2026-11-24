require "csv"

# Loads the assignment CSVs into the database, replacing what is there.
class Importer
  DATA_DIR = Rails.root.join("db/data")
  FILES = { "partners" => Partner, "leads" => Lead, "events" => Event, "calls" => Call, "billing" => BillingLine }.freeze

  def self.call(dir = DATA_DIR)
    ApplicationRecord.transaction do
      FILES.each do |file, model|
        model.delete_all
        rows = CSV.foreach(File.join(dir, "#{file}.csv"), headers: true).map { |r| r.to_h.transform_values(&:presence) }
        model.insert_all!(rows) if rows.any?
      end
    end
    ApplicationRecord.connection.execute("ANALYZE") # without stats SQLite picks the wrong index (40x slower)
    FILES.to_h { |file, model| [file, model.count] }
  end
end
