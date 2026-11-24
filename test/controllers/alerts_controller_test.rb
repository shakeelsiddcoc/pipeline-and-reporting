require "test_helper"

class AlertsControllerTest < ActionDispatch::IntegrationTest
  test "lists alerts" do
    Lead.create!(lead_id: "L1", publisher_id: "P2", received_at: Time.utc(2026, 10, 5, 9), accepted: true)
    Alert.create!(incident_key: "stall:routed:P2", check_name: "stall", severity: "critical", partner_id: "P2",
                  affected_count: 23, sample_ids: %w[L1], detected_at: Time.utc(2026, 10, 8, 14, 15),
                  last_new_at: Time.utc(2026, 10, 8, 18))
    get alerts_path
    assert_response :success
    assert_select ".badge", text: "Critical"
    assert_select "td", text: "Open"
  end

  test "empty state" do
    get alerts_path
    assert_response :success
    assert_match "No alerts yet", response.body
    assert_select "title", "Pipeline Health Alerts"
  end
end
