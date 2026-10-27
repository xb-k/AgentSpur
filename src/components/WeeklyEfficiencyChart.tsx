import React, { useEffect, useMemo, useRef, useState } from 'react';
import * as d3 from 'd3';
import { motion } from 'motion/react';
import { WeeklyEfficiencyPoint } from '../types/agent';

type ChartMetric = 'tasksPerHour' | 'avgSeconds';

interface WeeklyEfficiencyChartProps {
  data: WeeklyEfficiencyPoint[];
}

export const WeeklyEfficiencyChart: React.FC<WeeklyEfficiencyChartProps> = ({
  data,
}) => {
  const [metric, setMetric] = useState<ChartMetric>('tasksPerHour');
  const [hoveredIdx, setHoveredIdx] = useState<number | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const svgRef = useRef<SVGSVGElement | null>(null);
  const [width, setWidth] = useState<number>(920);

  // Measure responsive container width cleanly via ResizeObserver
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const updateWidth = () => {
      const nextW = Math.max(320, Math.floor(el.getBoundingClientRect().width));
      setWidth(nextW);
    };
    updateWidth();
    const ro = new ResizeObserver(updateWidth);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const totalCompleted = useMemo(
    () => data.reduce((sum, d) => sum + d.completedCount, 0),
    [data]
  );

  const avgDurationWeek = useMemo(() => {
    if (data.length === 0) return 0;
    return Math.round(
      data.reduce((sum, d) => sum + d.avgSeconds, 0) / data.length
    );
  }, [data]);

  const peakThroughput = useMemo(
    () => (data.length > 0 ? Math.max(...data.map((d) => d.tasksPerHour)) : 0),
    [data]
  );

  // Imperatively build and update D3.js SVG visualization
  useEffect(() => {
    const svgEl = svgRef.current;
    if (!svgEl || data.length === 0) return;

    const svg = d3.select(svgEl);
    svg.selectAll('*').remove();

    const height = 196;
    const margin = { top: 26, right: 24, bottom: 30, left: 40 };
    const innerW = Math.max(100, width - margin.left - margin.right);
    const innerH = height - margin.top - margin.bottom;

    const isThroughput = metric === 'tasksPerHour';
    const strokeColor = isThroughput ? '#0284C7' : '#059669';
    const gradId = isThroughput
      ? 'agentspur-eff-grad-sky'
      : 'agentspur-eff-grad-emerald';

    // Gradient definition
    const defs = svg.append('defs');
    const gradient = defs
      .append('linearGradient')
      .attr('id', gradId)
      .attr('x1', '0%')
      .attr('y1', '0%')
      .attr('x2', '0%')
      .attr('y2', '100%');

    gradient
      .append('stop')
      .attr('offset', '0%')
      .attr('stop-color', strokeColor)
      .attr('stop-opacity', 0.16);

    gradient
      .append('stop')
      .attr('offset', '100%')
      .attr('stop-color', strokeColor)
      .attr('stop-opacity', 0.0);

    const g = svg
      .append('g')
      .attr('transform', `translate(${margin.left},${margin.top})`);

    const xScale = d3
      .scalePoint<string>()
      .domain(data.map((d) => d.day))
      .range([0, innerW])
      .padding(0.18);

    const values = data.map((d) =>
      isThroughput ? d.tasksPerHour : d.avgSeconds
    );
    const minVal = d3.min(values) ?? 0;
    const maxVal = d3.max(values) ?? 10;

    const yScale = d3
      .scaleLinear()
      .domain([Math.max(0, Math.floor(minVal * 0.75)), Math.ceil(maxVal * 1.15)])
      .nice(4)
      .range([innerH, 0]);

    // Subtle horizontal hairline gridlines + Y-axis labels
    const yTicks = yScale.ticks(4);
    g.selectAll('.grid-line')
      .data(yTicks)
      .enter()
      .append('line')
      .attr('x1', 0)
      .attr('x2', innerW)
      .attr('y1', (t) => yScale(t))
      .attr('y2', (t) => yScale(t))
      .attr('stroke', 'rgba(15, 23, 42, 0.06)')
      .attr('stroke-dasharray', '3,3');

    g.selectAll('.y-label')
      .data(yTicks)
      .enter()
      .append('text')
      .attr('x', -10)
      .attr('y', (t) => yScale(t))
      .attr('dy', '0.32em')
      .attr('text-anchor', 'end')
      .attr('fill', '#94A3B8')
      .attr('font-family', '"JetBrains Mono", monospace')
      .attr('font-size', '10px')
      .text((t) => (isThroughput ? `${t}` : `${t}s`));

    // X-axis day labels
    g.selectAll('.x-label')
      .data(data)
      .enter()
      .append('text')
      .attr('x', (d) => xScale(d.day) ?? 0)
      .attr('y', innerH + 20)
      .attr('text-anchor', 'middle')
      .attr('fill', (d, i) =>
        hoveredIdx === i ? '#0F172A' : d.isToday ? '#0284C7' : '#64748B'
      )
      .attr('font-weight', (d, i) =>
        hoveredIdx === i || d.isToday ? '600' : '400'
      )
      .attr('font-size', '11px')
      .text((d) => (d.isToday ? `${d.day} · 今` : d.day));

    // Smooth D3 area generator
    const areaGen = d3
      .area<WeeklyEfficiencyPoint>()
      .x((d) => xScale(d.day) ?? 0)
      .y0(innerH)
      .y1((d) => yScale(isThroughput ? d.tasksPerHour : d.avgSeconds))
      .curve(d3.curveMonotoneX);

    g.append('path')
      .datum(data)
      .attr('fill', `url(#${gradId})`)
      .attr('d', areaGen);

    // Smooth D3 line generator
    const lineGen = d3
      .line<WeeklyEfficiencyPoint>()
      .x((d) => xScale(d.day) ?? 0)
      .y((d) => yScale(isThroughput ? d.tasksPerHour : d.avgSeconds))
      .curve(d3.curveMonotoneX);

    g.append('path')
      .datum(data)
      .attr('fill', 'none')
      .attr('stroke', strokeColor)
      .attr('stroke-width', 2.2)
      .attr('stroke-linecap', 'round')
      .attr('d', lineGen);

    // Hover vertical guide & floating SVG callout
    if (hoveredIdx !== null && data[hoveredIdx]) {
      const hd = data[hoveredIdx];
      const hx = xScale(hd.day) ?? 0;
      const hy = yScale(isThroughput ? hd.tasksPerHour : hd.avgSeconds);

      g.append('line')
        .attr('x1', hx)
        .attr('x2', hx)
        .attr('y1', 0)
        .attr('y2', innerH)
        .attr('stroke', 'rgba(15, 23, 42, 0.14)')
        .attr('stroke-width', 1)
        .attr('stroke-dasharray', '2,2');

      // Soft outer halo on hovered point
      g.append('circle')
        .attr('cx', hx)
        .attr('cy', hy)
        .attr('r', 8)
        .attr('fill', strokeColor)
        .attr('fill-opacity', 0.14);

      // Crisp SVG floating callout pill above point (clamped inside innerW)
      const boxW = 148;
      const boxH = 38;
      const clampedX = Math.max(
        0,
        Math.min(innerW - boxW, hx - boxW / 2)
      );
      const boxY = hy > 50 ? hy - boxH - 12 : hy + 12;

      const callout = g
        .append('g')
        .attr('transform', `translate(${clampedX},${boxY})`);

      callout
        .append('rect')
        .attr('width', boxW)
        .attr('height', boxH)
        .attr('rx', 8)
        .attr('fill', 'rgba(255, 255, 255, 0.96)')
        .attr('stroke', 'rgba(15, 23, 42, 0.08)');

      callout
        .append('text')
        .attr('x', 10)
        .attr('y', 15)
        .attr('fill', '#64748B')
        .attr('font-size', '10px')
        .attr('font-family', '"JetBrains Mono", monospace')
        .text(`${hd.day} (${hd.dateShort}) · 完成 ${hd.completedCount}`);

      callout
        .append('text')
        .attr('x', 10)
        .attr('y', 29)
        .attr('fill', '#0F172A')
        .attr('font-size', '11px')
        .attr('font-weight', '600')
        .attr('font-family', '"JetBrains Mono", monospace')
        .text(`${hd.tasksPerHour.toFixed(1)} 项/时 · 均耗 ${hd.avgSeconds}s`);
    }

    // Data nodes
    g.selectAll('.data-node')
      .data(data)
      .enter()
      .append('circle')
      .attr('cx', (d) => xScale(d.day) ?? 0)
      .attr('cy', (d) => yScale(isThroughput ? d.tasksPerHour : d.avgSeconds))
      .attr('r', (_, i) => (hoveredIdx === i ? 4.5 : 3.2))
      .attr('fill', '#FFFFFF')
      .attr('stroke', strokeColor)
      .attr('stroke-width', (_, i) => (hoveredIdx === i ? 2.4 : 1.8));

    // Invisible interactive hover columns across chart width
    const stepW = innerW / data.length;
    g.selectAll('.hit-zone')
      .data(data)
      .enter()
      .append('rect')
      .attr('x', (d) => (xScale(d.day) ?? 0) - stepW / 2)
      .attr('y', 0)
      .attr('width', stepW)
      .attr('height', innerH + 24)
      .attr('fill', 'transparent')
      .attr('cursor', 'pointer')
      .on('mouseenter', (_, d) => {
        const idx = data.findIndex((item) => item.day === d.day);
        setHoveredIdx(idx);
      })
      .on('mouseleave', () => {
        setHoveredIdx(null);
      });
  }, [data, metric, width, hoveredIdx]);

  return (
    <section
      aria-label="本周任务处理效率折线图分析"
      className="w-full rounded-2xl border border-black/[0.06] bg-white/82 p-6 shadow-[0_20px_50px_-15px_rgba(15,23,42,0.07)] backdrop-blur-3xl select-none text-slate-900"
    >
      <div className="flex flex-wrap items-center justify-between gap-4 pb-3">
        <div className="space-y-0.5">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="text-sm font-semibold text-slate-900">
              本周任务处理效率分析
            </h2>
            <span className="text-slate-300" aria-hidden="true">
              ·
            </span>
            <span className="text-xs text-slate-500 font-mono tabular-nums">
              累计完成 {totalCompleted} 项 · 均耗 {avgDurationWeek}s · 峰值{' '}
              {peakThroughput.toFixed(1)} 项/时
            </span>
          </div>
          <p className="text-[11px] text-slate-400">
            基于本机 opencode 会话完成记录生成（悬停节点查看单日吞吐与平均耗时）
          </p>
        </div>

        {/* Fluid Minimalist Metric Switcher */}
        <div
          role="tablist"
          aria-label="切换效率指标"
          className="inline-flex items-center gap-0.5 rounded-lg bg-slate-900/[0.045] p-0.5 text-xs"
        >
          {(
            [
              { id: 'tasksPerHour', label: '吞吐效率 (项/时)' },
              { id: 'avgSeconds', label: '平均耗时 (秒)' },
            ] as const
          ).map((item) => {
            const active = metric === item.id;
            return (
              <button
                key={item.id}
                role="tab"
                type="button"
                aria-selected={active}
                onClick={() => setMetric(item.id)}
                className={`relative rounded-md px-2.5 py-1 text-[11px] font-medium transition-colors whitespace-nowrap shrink-0 ${
                  active
                    ? 'text-slate-900'
                    : 'text-slate-500 hover:text-slate-800'
                }`}
              >
                {active && (
                  <motion.span
                    layoutId="efficiencyMetricTab"
                    transition={{ duration: 0.16, ease: [0.16, 1, 0.3, 1] }}
                    className="absolute inset-0 rounded-md bg-white shadow-[0_1px_3px_rgba(15,23,42,0.08)]"
                  />
                )}
                <span className="relative z-10">{item.label}</span>
              </button>
            );
          })}
        </div>
      </div>

      <div ref={containerRef} className="w-full overflow-hidden">
        <svg
          ref={svgRef}
          viewBox={`0 0 ${width} 196`}
          className="w-full h-[196px] overflow-visible"
          role="img"
          aria-label="AgentSpur 本周任务处理效率 D3.js 折线图"
        />
      </div>
    </section>
  );
};
