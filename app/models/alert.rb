class Alert < ApplicationRecord
  SEVERITIES = %w[medium high critical].freeze
  attr_accessor :ids, :missed, :recent, :confirm, :peak, :baseline_end # in-memory incident state for HealthMonitor::Runner
end
