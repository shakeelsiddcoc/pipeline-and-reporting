require "test_helper"

class BillingControllerTest < ActionDispatch::IntegrationTest
  test "shows a decision per line" do
    Importer.call
    get billing_path
    assert_response :success
    assert_select "tbody tr", 9
    assert_select "td .st-critical", 2
  end

  test "empty state" do
    get billing_path
    assert_match "No billing data", response.body
  end
end
