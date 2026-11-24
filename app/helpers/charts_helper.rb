# Server-rendered SVG/HTML charts, so the pages need no JS library or CDN.
# Specs follow the dataviz guidance: hairline grid, 2px lines, <=24px bars with 4px rounded data-ends,
# 2px surface gaps between stacked segments, a legend for 2+ series, a table view, hover via data-tip.
module ChartsHelper
  CHART_W = 640
  PAD = { l: 52, r: 30, t: 16, b: 30 }.freeze # r leaves room for the last x label, centered on the last point
  STATUS_ICONS = {
    "critical" => "M5 1h6l4 4v6l-4 4H5l-4-4V5z",                  # octagon
    "serious" => "M8 1.5l7 13H1z",                              # triangle
    "warning" => "M8 1.5a6.5 6.5 0 1 1 0 13a6.5 6.5 0 1 1 0-13z", # circle
    "good" => "M2 8.5l4 4 8-9"                                  # check
  }.freeze
  SEVERITY_STATUS = { "critical" => "critical", "high" => "serious", "medium" => "warning" }.freeze
  DECISION_STATUS = { "approve" => "good", "dispute" => "critical", "hold" => "warning" }.freeze

  # P1/B1/I1 -> slot 1, P2 -> slot 2 ...: color follows the entity, never its rank.
  def series_slot(partner_id) = partner_id.to_s[/\d+/].to_i.clamp(1, 8)

  def fmt_value(v, format = :int)
    return "—" if v.nil?
    case format
    when :pct then number_to_percentage(v * 100, precision: 1)
    when :usd then number_to_currency(v, precision: 0)
    else number_with_delimiter(v.round)
    end
  end

  def fmt_tick(v, format)
    case format
    when :pct then "#{(v * 100).round}%"
    when :usd then v >= 1000 ? "$#{(v / 1000.0).round(1).to_s.delete_suffix('.0')}K" : "$#{v.round}"
    else v >= 10_000 ? "#{(v / 1000.0).round}K" : number_with_delimiter(v.round)
    end
  end

  def nice_ceiling(v)
    return 1 if v.nil? || v <= 0
    mag = 10**Math.log10(v).floor
    [1, 2, 2.5, 5, 10].map { |m| m * mag }.find { |n| n >= v }
  end

  def card(title, subtitle = nil, css: nil, &block)
    tag.section(class: ["card", css]) do
      tag.header(class: "card-head") { tag.h3(title) + (subtitle ? tag.p(subtitle, class: "sub") : "".html_safe) } + capture(&block)
    end
  end

  def status_badge(label, status)
    tag.span(class: "badge st-#{status}") do
      tag.svg(tag.path(d: STATUS_ICONS.fetch(status)), viewBox: "0 0 16 16", class: "badge-icon", "aria-hidden": true) + label.to_s.humanize
    end
  end

  def severity_badge(sev) = status_badge(sev, SEVERITY_STATUS.fetch(sev))
  def decision_badge(dec) = status_badge(dec, DECISION_STATUS.fetch(dec))

  # Chart annotation from the monitor's own alerts, so the "why" under a chart never goes stale.
  def alert_notes(alerts, *checks)
    hits = alerts.select { |a| checks.include?(a.check_name) }
    return "".html_safe if hits.empty?
    tag.ul(class: "story") do
      safe_join(hits.map do |a|
        tag.li { severity_badge(a.severity) + " #{a.partner_id} · #{a.detected_at.strftime('%a %H:%M')} · #{a.detail}" }
      end)
    end
  end

  # Signed change vs a named period; color = direction x whether up is good. Arrow + text, never color alone.
  def kpi_delta(curr, prev, vs:, format: :int, up_is_good: true)
    return tag.span("no #{vs} to compare", class: "delta flat") if prev.nil? || curr.nil?
    diff = curr - prev
    return tag.span("no change vs #{vs}", class: "delta flat") if diff.abs < (format == :pct ? 0.0005 : 0.5)
    text = format == :pct ? "#{format('%+.1f', diff * 100)} pts" : (format == :usd ? "#{diff.positive? ? '+' : '−'}#{number_to_currency(diff.abs, precision: 0)}" : format("%+d", diff.round))
    good = diff.positive? == up_is_good
    tag.span("#{diff.positive? ? '▲' : '▼'} #{text} vs #{vs}", class: "delta #{good ? 'good' : 'bad'}")
  end

  def chart_legend(series, kind: :bar)
    tag.ul(class: "legend") do
      safe_join(series.map { |s| tag.li { tag.span(class: "key key-#{kind} s#{s[:slot]}") + s[:name] } })
    end
  end

  # Multi-series line chart with a per-X hover band (crosshair + every series in one tooltip).
  # Points that sit far below their own series' median, as chart notes: [{series:, at:, text:}].
  # Data-driven, so a normal week draws no notes. Only the first of a run of lows is labeled.
  def outlier_notes(series, format:, drop:)
    series.each_with_index.filter_map do |s, si|
      vals = s[:values].compact
      next if vals.size < 3
      median = vals.sort[vals.size / 2]
      low = s[:values].each_with_index.select { |v, _| v && median - v >= drop }.min_by { |v, i| [v, i] }
      next unless low
      { series: si, at: low[1], text: "#{s[:name].split.first} #{fmt_tick(low[0], format)} (normal #{fmt_tick(median, format)})" }
    end
  end

  def line_chart(labels:, series:, title:, format: :int, y_min: 0, y_max: nil, height: 230, notes: [])
    pw, ph = plot_size(height)
    y_max ||= nice_ceiling(series.flat_map { |s| s[:values] }.compact.max)
    xs = labels.each_index.map { |i| PAD[:l] + (labels.size > 1 ? pw * i / (labels.size - 1.0) : pw / 2.0) }
    yv = ->(v) { (PAD[:t] + ph * (1 - (v - y_min) / (y_max - y_min).to_f)).round(1) }
    parts = [grid(y_min, y_max, format, pw, ph), x_labels(labels, xs, height)]
    series.each do |s|
      pts = s[:values].each_with_index.filter_map { |v, i| [xs[i].round(1), yv.(v)] if v }
      parts << tag.polyline(points: pts.map { |p| p.join(",") }.join(" "), class: "ln s#{s[:slot]}")
      pts.each { |x, y| parts << tag.circle(cx: x, cy: y, r: 4, class: "dot s#{s[:slot]}") }
    end
    notes.each do |n|
      v = series[n[:series]][:values][n[:at]]
      next unless v
      px, py = xs[n[:at]], yv.(v)
      w = n[:text].length * 6.3 + 14 # shortcut: estimated text width (11px Plex), fine for short notes
      lx = (px - w / 2).clamp(PAD[:l], CHART_W - PAD[:r] - w)
      ly = py > PAD[:t] + ph / 2 ? py - 40 : py + 18 # label above low points, below high ones
      parts << tag.circle(cx: px.round(1), cy: py, r: 8, class: "note-ring") +
               tag.line(x1: px.round(1), y1: (ly > py ? py + 8 : py - 8).round(1), x2: px.round(1), y2: (ly > py ? ly : ly + 22).round(1), class: "note-lead") +
               tag.rect(x: lx.round(1), y: ly.round(1), width: w.round(1), height: 22, rx: 11, class: "note-bg") +
               tag.text(n[:text], x: (lx + w / 2).round(1), y: (ly + 15).round(1), class: "note-text", "text-anchor": "middle")
    end
    band = pw / [labels.size - 1, 1].max.to_f
    labels.each_with_index do |label, i|
      rows = series.map { |s| [s[:name], fmt_value(s[:values][i], format), s[:slot]] }
      x = xs[i].round(1)
      parts << hit_band(xs[i] - band / 2, band, ph, label, rows,
                        tag.line(x1: x, x2: x, y1: PAD[:t], y2: PAD[:t] + ph, class: "xhair"))
    end
    chart_svg(height, title, parts)
  end

  # Stacked column chart; the total sits on each cap.
  def column_chart(labels:, series:, title:, format: :int, height: 230)
    pw, ph = plot_size(height)
    totals = labels.each_index.map { |i| series.sum { |s| s[:values][i].to_f } }
    y_max = nice_ceiling(totals.max)
    band = pw / labels.size.to_f
    bw = [band * 0.5, 24].min
    centers = labels.each_index.map { |i| PAD[:l] + band * (i + 0.5) }
    parts = [grid(0, y_max, format, pw, ph), x_labels(labels, centers, height)]
    labels.each_with_index do |label, i|
      cx = centers[i]
      base = PAD[:t] + ph
      top = series.rindex { |s| s[:values][i].to_f.positive? }
      series.each_with_index do |s, si|
        v = s[:values][i].to_f
        next unless v.positive?
        h = ph * v / y_max
        y = base - h
        parts << if si == top
          tag.path(d: top_rounded(cx - bw / 2, y, bw, h), class: "bar s#{s[:slot]}")
        else # 2px surface gap above every segment that has another stacked on it
          tag.rect(x: (cx - bw / 2).round(1), y: (y + 2).round(1), width: bw.round(1),
                   height: [h - 2, 0].max.round(1), class: "bar s#{s[:slot]}")
        end
        base = y
      end
      parts << tag.text(fmt_value(totals[i], format), x: cx.round(1), y: (base - 6).round(1), class: "cap", "text-anchor": "middle")
      rows = series.map { |s| [s[:name], fmt_value(s[:values][i].to_f, format), s[:slot]] } +
             [["Total", fmt_value(totals[i], format), nil]]
      parts << hit_band(PAD[:l] + band * i, band, ph, label, rows)
    end
    chart_svg(height, title, parts)
  end

  # Horizontal bars in HTML (scales to any width). rows: [{label:, value:, note:}]; one series = one hue.
  def hbar_list(rows, format: :int, slot: 1)
    max = rows.map { |r| r[:value].to_f }.max.to_f
    tag.div(class: "hbars") do
      safe_join(rows.map do |r|
        pct = max.positive? ? (100.0 * r[:value].to_f / max).round(2) : 0
        tag.div(class: "hbar") do
          tag.span(r[:label], class: "hbar-label") +
            tag.span(class: "hbar-track") { pct.positive? ? tag.span(class: "hbar-fill s#{slot}", style: "width:#{pct}%") : "".html_safe } +
            tag.span(class: "hbar-value") { fmt_value(r[:value], format) + (r[:note] ? tag.small(r[:note]) : "".html_safe) }
        end
      end)
    end
  end

  def sparkline(values, w: 112, h: 32)
    vals = values.map(&:to_f)
    min, max = vals.minmax
    span = (max - min).zero? ? 1 : max - min
    pts = vals.each_with_index.map do |v, i|
      [(3 + (w - 6) * i / [vals.size - 1, 1].max.to_f).round(1), (3 + (h - 6) * (1 - (v - min) / span)).round(1)]
    end
    tag.svg(viewBox: "0 0 #{w} #{h}", class: "spark", "aria-hidden": true) do
      tag.polyline(points: pts.map { |p| p.join(",") }.join(" "), class: "spark-ln") +
        tag.circle(cx: pts.last[0], cy: pts.last[1], r: 3, class: "spark-end")
    end
  end

  # The same numbers as the chart, so nothing depends on hover or on telling colors apart.
  def chart_table(labels, series, format: :int)
    tag.details(class: "tableview") do
      tag.summary("Show data table") + tag.div(class: "wrap") do
        tag.table do
          tag.thead { tag.tr { tag.th("") + safe_join(labels.map { |l| tag.th(l, class: "num") }) } } +
            tag.tbody do
              safe_join(series.map do |s|
                tag.tr { tag.th(s[:name]) + safe_join(s[:values].map { |v| tag.td(fmt_value(v, format), class: "num") }) }
              end)
            end
        end
      end
    end
  end

  private

  def plot_size(height) = [CHART_W - PAD[:l] - PAD[:r], height - PAD[:t] - PAD[:b]]

  def chart_svg(height, title, parts)
    tag.div(class: "chart-scroll") do
      tag.svg(safe_join(parts), viewBox: "0 0 #{CHART_W} #{height}", class: "chart", role: "img", "aria-label": title)
    end
  end

  def grid(y_min, y_max, format, pw, ph, steps: 4)
    safe_join((0..steps).map do |k|
      y = (PAD[:t] + ph * (1 - k / steps.to_f)).round(1)
      tag.line(x1: PAD[:l], x2: PAD[:l] + pw, y1: y, y2: y, class: k.zero? ? "axis" : "gridline") +
        tag.text(fmt_tick(y_min + (y_max - y_min) * k / steps.to_f, format), x: PAD[:l] - 8, y: y + 4,
                 class: "tick", "text-anchor": "end")
    end)
  end

  def x_labels(labels, xs, height)
    safe_join(labels.each_with_index.map { |l, i| tag.text(l, x: xs[i].round(1), y: height - 8, class: "tick", "text-anchor": "middle") })
  end

  def hit_band(x, w, ph, label, rows, extra = "".html_safe)
    tag.g(class: "hit", tabindex: 0, data: { tip: { title: label, rows: rows }.to_json },
          "aria-label": "#{label}: #{rows.map { |n, v, _| "#{n} #{v}" }.join(', ')}") do
      tag.rect(x: x.round(1), y: PAD[:t], width: w.round(1), height: ph, class: "hit-area") + extra
    end
  end

  def top_rounded(x, y, w, h, r = 4)
    r = [r, h, w / 2].min
    x, y, w, h, r = [x, y, w, h, r].map { |n| n.round(1) }
    "M#{x},#{(y + h).round(1)}V#{(y + r).round(1)}Q#{x},#{y} #{(x + r).round(1)},#{y}H#{(x + w - r).round(1)}" \
      "Q#{(x + w).round(1)},#{y} #{(x + w).round(1)},#{(y + r).round(1)}V#{(y + h).round(1)}Z"
  end
end
