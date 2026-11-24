require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  test "shows the requested day with all sections" do
    Importer.call
    get report_path("2026-10-07")
    assert_response :success
    assert_select ".wday[aria-current] .wname", text: "Wed 7"
    assert_select "h2", count: 4
    assert_select ".kpi", 6
    assert_select ".delta.bad", minimum: 1 # Wed: P3 consent drop pulls acceptance down vs Tue
    assert_select "tr.total", count: 4
  end

  test "unknown day falls back to latest; empty db renders" do
    get report_path("nope")
    assert_response :success
    assert_match "No data loaded", response.body
  end
end
