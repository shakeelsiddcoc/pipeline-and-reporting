class Alert < ApplicationRecord
  SEVERITIES = %w[medium high critical].freeze
  attr_accessor :ids, :missed, :streak # in-memory incident state used by HealthMonitor::Runner
end
