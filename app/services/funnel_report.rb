# Part B: runs the SQL in app/queries/funnel and returns rows as hashes.
class FunnelReport
  SECTIONS = {
    "leads" => "Leads received, accepted, rejected (by received date, per publisher)",
    "stages" => "Pipeline funnel (accepted leads by received date)",
    "deliveries" => "Signed cases delivered (each lead once, by first delivery date, per buyer)",
    "calls" => "Inbound calls (by call date, per publisher)"
  }.freeze
  BINDS = { case_price: PipelineRules::CASE_PRICE, call_price: PipelineRules::CALL_PRICE,
            billable_sec: PipelineRules::BILLABLE_CALL_SEC }.freeze

  def self.sql(section) = Rails.root.join("app/queries/funnel/#{section}.sql").read

  def self.rows(section)
    query = sql(section)
    binds = BINDS.select { |k, _| query.include?(":#{k}") }
    ApplicationRecord.connection.select_all(ApplicationRecord.sanitize_sql([query, binds])).to_a
  end

  def self.all = SECTIONS.keys.to_h { |s| [s, rows(s)] }
end
