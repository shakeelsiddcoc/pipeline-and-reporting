module HealthMonitor
  # Replays the week on a 15-minute clock. Findings with the same key across ticks form one
  # incident (one alert), so a 4-hour outage is 1 alert, not 16. An incident resolves after
  # RESOLVE_AFTER consecutive clean ticks.
  class Runner
    TICK = 15.minutes
    RESOLVE_AFTER = 4 # 1 hour clean; shorter splits one bad day into several alerts when volume dips
    CHECKS = [Checks::Stall, Checks::DuplicateDelivery, Checks::AcceptanceDrop,
              Checks::ConversionDrop, Checks::BrokenSequence, Checks::Misrouting].freeze

    def self.call(...) = new.call(...)

    def call(from: default_from, to: default_to)
      open = {}
      closed = []
      (0..((to - from) / TICK)).each do |i|
        t = from + i * TICK
        seen = CHECKS.flat_map { |c| c.new(t).findings }.index_by(&:key)
        seen.each_value { |f| observe(open[f.key] ||= new_alert(f), f, t) }
        open.each_value { |a| seen.key?(a.incident_key) ? a.missed = 0 : (a.missed += 1; a.streak = 0) }
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
      Alert.new(incident_key: f.key, check_name: f.check, partner_id: f.partner_id, severity: f.severity)
           .tap { |a| a.ids = []; a.missed = 0; a.streak = 0 }
    end

    def observe(a, f, t)
      a.streak += 1
      a.detected_at ||= t if a.streak >= f.confirm
      fresh = f.ids - a.ids
      a.ids.concat(fresh)
      a.last_new_at = t if fresh.any?
      a.detail = f.detail
      a.severity = [a.severity, f.severity].max_by { |s| Alert::SEVERITIES.index(s) }
    end

    def default_from = [Lead.minimum(:received_at), Call.minimum(:started_at)].min.beginning_of_day

    def default_to
      last = [Event.maximum(:occurred_at), Lead.maximum(:received_at), Call.maximum(:started_at)].max
      last.beginning_of_hour + 1.hour + RESOLVE_AFTER * TICK
    end
  end
end
