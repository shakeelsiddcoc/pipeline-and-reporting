module HealthMonitor
  # Shared rule for "rate moved sharply from its normal level".
  # Baseline = everything before the window, so the monitor learns "normal" as the week goes.
  # Fires only when the window is big enough AND the drop is large AND it is statistically
  # unlikely (one-sided z >= 3, ~0.1% chance per window if nothing changed).
  module RateDrop
    MIN_WINDOW_N = 20  # below this, 5 random rejects already look like a 25pp drop
    MIN_BASELINE_N = 50
    MIN_ABS_DROP = 0.20
    MIN_Z = 3.0
    CONFIRM_TICKS = 2 # must hold for 30 min; a single noisy window never pages anyone

    def self.drop(n:, hits:, base_n:, base_hits:)
      return if n < MIN_WINDOW_N || base_n < MIN_BASELINE_N
      rate = hits.fdiv(n)
      base = base_hits.fdiv(base_n)
      return if base - rate < MIN_ABS_DROP
      sd = Math.sqrt(base * (1 - base) / n)
      z = sd.zero? ? Float::INFINITY : (base - rate) / sd
      return if z < MIN_Z
      { rate: rate, base: base, z: z }
    end

    def self.describe(label, n, d)
      format("%s %.0f%% over last %d (normal %.0f%%, z=%.1f)", label, d[:rate] * 100, n, d[:base] * 100, d[:z])
    end
  end
end
