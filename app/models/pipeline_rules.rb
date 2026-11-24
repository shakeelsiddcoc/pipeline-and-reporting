# Business rules from the assignment brief.
module PipelineRules
  STAGES = %w[verified routed contacted qualified retainer_sent signed delivered].freeze
  ROUTING = {
    "TX" => { intake: "I1", buyer: "B1" },
    "GA" => { intake: "I1", buyer: "B1" },
    "AZ" => { intake: "I1", buyer: "B1" },
    "FL" => { intake: "I2", buyer: "B2" },
    "CA" => { intake: "I2", buyer: "B3" }
  }.freeze
  LEAD_PRICE = 35
  CALL_PRICE = 60
  CASE_PRICE = 3000
  BILLABLE_CALL_SEC = 90

  # SQL CTE of the routing table, so checks can join against it.
  def self.routing_cte
    rows = ROUTING.map { |s, r| "('#{s}','#{r[:intake]}','#{r[:buyer]}')" }.join(",")
    "routing(state, intake, buyer) AS (VALUES #{rows})"
  end
end
