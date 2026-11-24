require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "overview renders KPIs, six charts with tables, and incidents" do
    Importer.call
    HealthMonitor::Runner.call
    get root_path
    assert_response :success
    assert_select ".kpi.hero .kpi-value", "$210,000" # 70 cases delivered inside the week
    assert_select "svg.chart", 5                    # 3 column + 2 line charts; the funnel is HTML bars
    assert_select ".hbars", 1
    assert_select "details.tableview", 5
    assert_select ".hit[data-tip]", minimum: 35     # one hover band per day per chart
    assert_select ".story li", 7                     # every incident annotates a chart
  end

  test "empty database" do
    get root_path
    assert_response :success
    assert_match "No data loaded", response.body
  end
end
