module HealthMonitor
  # Replays the week on a 15-minute clock. Findings with the same key across ticks form one
  # incident (one alert), so a 4-hour outage is 1 alert, not 16. An incident resolves after
  # RESOLVE_AFTER consecutive clean ticks. Checks only look at recent activity (their own lookback),
  # so "resolved" means "stopped happening"; leads still stuck afterwards are in Backlog, not here.
  class Runner
    TICK = 15.minutes
    RESOLVE_AFTER = 4 # 1 hour clean; shorter splits one bad day into several alerts when volume dips
    CONFIRM_OF = 3    # a finding confirms when seen in `confirm` of the last 3 ticks, so a flapping one still alerts
    CHECKS = [Checks::Stall, Checks::DuplicateDelivery, Checks::AcceptanceDrop, Checks::ConversionDrop,
              Checks::BrokenSequence, Checks::Misrouting, Checks::Silence, Checks::FailedEvents].freeze

    def self.call(...) = new.call(...)

    # Leads still stuck past an SLA at the end of the data, whether or not anything is still breaking.
    def self.backlog(at = data_end) = Checks::Stall.new(at, backlog: true).findings

    def self.data_end = [Event.maximum(:occurred_at), Lead.maximum(:received_at), Call.maximum(:started_at)].compact.max

    def call(from: default_from, to: default_to, checks: CHECKS)
      open = {}
      closed = []
      (0..((to - from) / TICK)).each do |i|
        t = from + i * TICK
        frozen = open.transform_values(&:baseline_end).compact
        seen = checks.flat_map { |c| c.new(t, frozen: frozen).findings }.index_by(&:key)
        seen.each_value { |f| observe(open[f.key] ||= new_alert(f), f, t) }
        open.each_value do |a|
          hit = seen.key?(a.incident_key)
          a.recent = (a.recent + [hit]).last(CONFIRM_OF)
          a.missed = hit ? 0 : a.missed + 1
          a.detected_at ||= t if hit && a.recent.count(true) >= a.confirm
        end
        open.select { |_, a| a.missed >= RESOLVE_AFTER }.each do |key, a|
          a.resolved_at = t
          closed << open.delete(key)
        end
      end
      alerts = (closed + open.values).select(&:detected_at).sort_by(&:detected_at) # unconfirmed blips dropped
      Alert.transaction do
        Alert.delete_all
        alerts.each { |a| a.affected_count = a.ids.size; a.sample_ids = a.ids.first(5); a.save! }
      end
      alerts
    end

    private

    def new_alert(f)
      Alert.new(incident_key: f.key, check_name: f.check, partner_id: f.partner_id, severity: f.severity).tap do |a|
        a.ids = []
        a.recent = []
        a.missed = 0
        a.confirm = f.confirm
        a.baseline_end = f.baseline_end # first sighting's baseline is the one we keep judging against
      end
    end

    def observe(a, f, t)
      fresh = f.ids - a.ids
      a.ids.concat(fresh)
      a.last_new_at = t if fresh.any? || f.ids.empty? # ID-less findings (silence): last tick it was seen
      if a.peak.nil? || f.score >= a.peak # keep the worst tick's detail, not the tail end's
        a.peak = f.score
        a.detail = f.detail
      end
      a.severity = [a.severity, f.severity].max_by { |s| Alert::SEVERITIES.index(s) }
    end

    def default_from = [Lead.minimum(:received_at), Call.minimum(:started_at)].min.beginning_of_day

    def default_to = self.class.data_end.beginning_of_hour + 1.hour + RESOLVE_AFTER * TICK
  end
end
