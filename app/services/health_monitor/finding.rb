module HealthMonitor
  # One problem seen by one check at one tick. `key` identifies the incident across ticks.
  # `confirm` = consecutive ticks it must be seen before it becomes an alert (filters one-tick blips).
  Finding = Struct.new(:check, :key, :severity, :partner_id, :ids, :detail, :confirm, keyword_init: true) do
    def initialize(confirm: 1, **) = super
  end
end
