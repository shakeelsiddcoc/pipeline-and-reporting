module HealthMonitor
  # Base for checks. A check sees only data with timestamps <= `at` (no look-ahead).
  # frozen: { incident_key => baseline_end } for rate incidents that are currently open.
  class Check
    attr_reader :at, :frozen

    def initialize(at, frozen: {})
      @at = at
      @frozen = frozen
    end

    def self.check_name = name.demodulize.underscore

    private

    def rows(query, **binds)
      ApplicationRecord.connection.select_all(ApplicationRecord.sanitize_sql([query, binds])).to_a
    end

    def full_key(key) = "#{self.class.check_name}:#{key}"

    def finding(key:, **attrs)
      Finding.new(check: self.class.check_name, key: full_key(key), **attrs)
    end

    # Groups [{partner_id:, <id_col>:}] rows into one finding per partner, if the count clears `min`.
    def per_partner(rows, id_col:, min:, key:, severity:, &detail)
      rows.group_by { |r| r["partner_id"] }.filter_map do |partner, rs|
        ids = rs.map { |r| r[id_col] }.uniq
        next if ids.size < min
        finding(key: "#{key}:#{partner}", partner_id: partner, ids: ids,
                severity: severity.respond_to?(:call) ? severity.call(ids.size) : severity,
                detail: detail.call(ids.size, rs))
      end
    end
  end
end
