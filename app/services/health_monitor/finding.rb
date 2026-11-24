module HealthMonitor
  # One problem seen by one check at one tick. `key` identifies the incident across ticks.
  # confirm: ticks (out of the last Runner::CONFIRM_OF) it must be seen in before it alerts.
  # score: how bad this tick is; the alert keeps the detail of its worst tick (default: affected count).
  # baseline_end: for rate checks, where the "normal" history ended; frozen while the incident is open.
  Finding = Struct.new(:check, :key, :severity, :partner_id, :ids, :detail, :confirm, :score, :baseline_end,
                       keyword_init: true) do
    def initialize(confirm: 1, score: nil, **rest) = super(confirm: confirm, score: score || rest[:ids].to_a.size, **rest)
  end
end
