import React, { useEffect, useRef } from 'react';
import { AgentStatus, CharacterPack } from '../types/agent';

// Shared 15 FPS ticker (66.67ms interval) — zero React state re-renders, direct canvas blit
type FrameSubscriber = (frame: number) => void;
const subscribers = new Set<FrameSubscriber>();
let globalFrame = 0;
let intervalId: number | null = null;

function subscribe15Fps(cb: FrameSubscriber): () => void {
  subscribers.add(cb);
  if (intervalId === null && typeof window !== 'undefined') {
    intervalId = window.setInterval(() => {
      globalFrame = (globalFrame + 1) % 15;
      subscribers.forEach((fn) => fn(globalFrame));
    }, 1000 / 15);
  }
  return () => {
    subscribers.delete(cb);
    if (subscribers.size === 0 && intervalId !== null) {
      window.clearInterval(intervalId);
      intervalId = null;
    }
  };
}

export function subscribeGlobalFrameIndex(cb: FrameSubscriber): () => void {
  return subscribe15Fps(cb);
}

interface AgentSpriteCanvasProps {
  status: AgentStatus;
  pack: CharacterPack;
  size?: number;
  fixedFrame?: number;
  monochrome?: boolean;
  className?: string;
}

function drawStatusOverlayBadge(
  ctx: CanvasRenderingContext2D,
  status: AgentStatus,
  frame: number,
  w: number,
  h: number
) {
  ctx.save();
  if (status === AgentStatus.Thinking) {
    const activeDot = Math.floor(frame / 5);
    for (let i = 0; i < 3; i++) {
      const alpha = i === activeDot ? 1 : 0.28;
      ctx.fillStyle = `rgba(2, 132, 199, ${alpha})`;
      ctx.beginPath();
      ctx.arc(w * 0.72 + i * (w * 0.09), h * (0.23 - i * 0.05), w * 0.044, 0, Math.PI * 2);
      ctx.fill();
    }
  } else if (status === AgentStatus.Confirm) {
    const pulse = 0.72 + 0.28 * Math.sin((frame / 15) * Math.PI * 2);
    ctx.fillStyle = `rgba(217, 119, 6, ${pulse})`;
    ctx.beginPath();
    ctx.arc(w * 0.81, h * 0.22, w * 0.12, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#FFFFFF';
    ctx.font = `700 ${Math.round(w * 0.18)}px "JetBrains Mono", monospace`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('?', w * 0.81, h * 0.23);
  } else if (status === AgentStatus.Completed) {
    const progress = Math.min(1, (frame + 3) / 8);
    ctx.strokeStyle = '#16A34A';
    ctx.lineWidth = Math.max(1.6, w * 0.092);
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.beginPath();
    ctx.moveTo(w * 0.66, h * 0.24);
    if (progress < 0.5) {
      const t = progress * 2;
      ctx.lineTo(w * (0.66 + 0.09 * t), h * (0.24 + 0.09 * t));
    } else {
      const t = (progress - 0.5) * 2;
      ctx.lineTo(w * 0.75, h * 0.33);
      ctx.lineTo(w * (0.75 + 0.16 * t), h * (0.33 - 0.18 * t));
    }
    ctx.stroke();
  } else if (status === AgentStatus.Error) {
    const flash = frame % 4 < 2 ? 1 : 0.45;
    ctx.strokeStyle = `rgba(220, 38, 38, ${flash})`;
    ctx.lineWidth = Math.max(1.6, w * 0.092);
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(w * 0.7, h * 0.14);
    ctx.lineTo(w * 0.88, h * 0.32);
    ctx.moveTo(w * 0.88, h * 0.14);
    ctx.lineTo(w * 0.7, h * 0.32);
    ctx.stroke();
  }
  ctx.restore();
}

// Fluid Minimalist Droplet ("Gin · 灵动微光") — Dynamic-Island-inspired elastic micro-spirit
function renderDropletArchetype(
  ctx: CanvasRenderingContext2D,
  status: AgentStatus,
  frame: number,
  w: number,
  h: number,
  primary: string,
  secondary: string
) {
  const cx = w * 0.48;
  const cy = h * 0.55;
  const t = (frame / 15) * Math.PI * 2;

  ctx.save();

  // Subtle ambient halo ring for Confirm / Working
  if (status === AgentStatus.Confirm) {
    const expand = (frame / 15) * (w * 0.16);
    const alpha = Math.max(0, 0.48 - (frame / 15) * 0.48);
    ctx.strokeStyle = `rgba(217, 119, 6, ${alpha})`;
    ctx.lineWidth = Math.max(1.2, w * 0.055);
    ctx.beginPath();
    ctx.arc(cx, cy, w * 0.3 + expand, 0, Math.PI * 2);
    ctx.stroke();
  } else if (status === AgentStatus.Working) {
    // Orbiting fluid satellite dot
    const ox = cx + Math.cos(t * 2) * (w * 0.38);
    const oy = cy + Math.sin(t * 2) * (h * 0.18);
    ctx.fillStyle = secondary;
    ctx.beginPath();
    ctx.arc(ox, oy, w * 0.055, 0, Math.PI * 2);
    ctx.fill();
  }

  // Elastic squash & stretch body transform
  const shakeX =
    status === AgentStatus.Error && frame < 6
      ? frame % 2 === 0
        ? -w * 0.055
        : w * 0.055
      : 0;
  const floatY =
    status === AgentStatus.Thinking
      ? Math.sin(t) * (h * 0.045)
      : status === AgentStatus.Confirm
      ? -Math.abs(Math.sin(t)) * (h * 0.065)
      : 0;

  const scaleX =
    status === AgentStatus.Working
      ? 1 + Math.sin(t * 2) * 0.08
      : 1 + Math.sin(t) * 0.03;
  const scaleY =
    status === AgentStatus.Working
      ? 1 - Math.sin(t * 2) * 0.08
      : 1 - Math.sin(t) * 0.03;

  ctx.translate(cx + shakeX, cy + floatY);
  ctx.scale(scaleX, scaleY);

  // Smooth rounded capsule-droplet core
  ctx.fillStyle =
    status === AgentStatus.Error
      ? '#DC2626'
      : status === AgentStatus.Completed
      ? '#0F172A'
      : primary;
  ctx.beginPath();
  ctx.arc(0, 0, w * 0.31, 0, Math.PI * 2);
  ctx.fill();

  // Minimalist luminous pill eyes
  ctx.fillStyle = '#FFFFFF';
  ctx.strokeStyle = '#FFFFFF';
  ctx.lineWidth = Math.max(1.3, w * 0.068);
  ctx.lineCap = 'round';

  const gazeX = status === AgentStatus.Thinking ? Math.sin(t) * (w * 0.045) : 0;
  const gazeY = status === AgentStatus.Thinking ? -h * 0.045 : 0;

  if (status === AgentStatus.Completed) {
    ctx.beginPath();
    ctx.arc(-w * 0.1, 0, w * 0.055, Math.PI * 1.15, Math.PI * 1.85);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(w * 0.1, 0, w * 0.055, Math.PI * 1.15, Math.PI * 1.85);
    ctx.stroke();
  } else if (status === AgentStatus.Error) {
    ctx.beginPath();
    ctx.moveTo(-w * 0.14, -h * 0.04);
    ctx.lineTo(-w * 0.06, h * 0.04);
    ctx.moveTo(-w * 0.06, -h * 0.04);
    ctx.lineTo(-w * 0.14, h * 0.04);
    ctx.moveTo(w * 0.06, -h * 0.04);
    ctx.lineTo(w * 0.14, h * 0.04);
    ctx.moveTo(w * 0.14, -h * 0.04);
    ctx.lineTo(w * 0.06, h * 0.04);
    ctx.stroke();
  } else {
    // Sleek vertical micro-pill eyes (blinking lightly on frame 13)
    const blinkScale = frame === 13 ? 0.25 : 1;
    const eyeH = h * 0.13 * blinkScale;
    ctx.beginPath();
    ctx.roundRect(-w * 0.125 + gazeX, -eyeH / 2 + gazeY, w * 0.062, eyeH, w * 0.03);
    ctx.roundRect(w * 0.063 + gazeX, -eyeH / 2 + gazeY, w * 0.062, eyeH, w * 0.03);
    ctx.fill();
  }

  ctx.restore();
  drawStatusOverlayBadge(ctx, status, frame, w, h);
}

function renderGlyphArchetype(
  ctx: CanvasRenderingContext2D,
  status: AgentStatus,
  frame: number,
  w: number,
  h: number,
  primary: string
) {
  const cx = w / 2;
  const cy = h / 2;
  const r = w * 0.36;
  ctx.save();
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  if (status === AgentStatus.Thinking) {
    const angle = (frame / 15) * Math.PI * 2;
    ctx.strokeStyle = primary;
    ctx.lineWidth = Math.max(1.5, w * 0.09);
    ctx.beginPath();
    ctx.arc(cx, cy, r, angle, angle + Math.PI * 1.45);
    ctx.stroke();

    for (let i = 0; i < 3; i++) {
      const active = Math.floor(frame / 5) === i;
      ctx.fillStyle = active ? '#0284C7' : 'rgba(15, 23, 42, 0.22)';
      ctx.beginPath();
      ctx.arc(cx + (i - 1) * (w * 0.14), cy, w * 0.05, 0, Math.PI * 2);
      ctx.fill();
    }
  } else if (status === AgentStatus.Working) {
    const barCount = 4;
    const spacing = w * 0.16;
    const startX = cx - ((barCount - 1) * spacing) / 2;
    for (let i = 0; i < barCount; i++) {
      const phase = ((frame + i * 3.5) / 15) * Math.PI * 2;
      const barH = h * (0.2 + 0.42 * (0.5 + 0.5 * Math.sin(phase)));
      ctx.strokeStyle = i === frame % 4 ? '#0284C7' : primary;
      ctx.lineWidth = Math.max(1.6, w * 0.092);
      ctx.beginPath();
      ctx.moveTo(startX + i * spacing, cy - barH / 2);
      ctx.lineTo(startX + i * spacing, cy + barH / 2);
      ctx.stroke();
    }
  } else if (status === AgentStatus.Confirm) {
    const wave = (frame / 15) * r * 0.45;
    const waveAlpha = Math.max(0, 0.65 - (frame / 15) * 0.65);
    ctx.strokeStyle = `rgba(217, 119, 6, ${waveAlpha})`;
    ctx.lineWidth = Math.max(1.1, w * 0.062);
    ctx.beginPath();
    ctx.arc(cx, cy, r + wave, 0, Math.PI * 2);
    ctx.stroke();

    ctx.strokeStyle = '#D97706';
    ctx.lineWidth = Math.max(1.5, w * 0.088);
    ctx.beginPath();
    ctx.arc(cx, cy, r * 0.88, 0, Math.PI * 2);
    ctx.stroke();

    ctx.fillStyle = '#B45309';
    ctx.font = `700 ${Math.round(w * 0.4)}px "JetBrains Mono", monospace`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('?', cx, cy + h * 0.02);
  } else if (status === AgentStatus.Completed) {
    ctx.strokeStyle = 'rgba(22, 163, 74, 0.28)';
    ctx.lineWidth = Math.max(1.3, w * 0.08);
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();

    const p = Math.min(1, (frame + 2) / 7);
    ctx.strokeStyle = '#16A34A';
    ctx.lineWidth = Math.max(1.7, w * 0.1);
    ctx.beginPath();
    ctx.moveTo(cx - r * 0.42, cy + r * 0.02);
    if (p < 0.45) {
      const t = p / 0.45;
      ctx.lineTo(cx - r * 0.42 + r * 0.32 * t, cy + r * 0.02 + r * 0.32 * t);
    } else {
      const t = (p - 0.45) / 0.55;
      ctx.lineTo(cx - r * 0.1, cy + r * 0.34);
      ctx.lineTo(cx - r * 0.1 + r * 0.62 * t, cy + r * 0.34 - r * 0.68 * t);
    }
    ctx.stroke();
  } else if (status === AgentStatus.Error) {
    const shake = frame < 6 ? (frame % 2 === 0 ? -w * 0.05 : w * 0.05) : 0;
    ctx.translate(shake, 0);
    ctx.strokeStyle = '#DC2626';
    ctx.lineWidth = Math.max(1.5, w * 0.09);
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();

    ctx.beginPath();
    ctx.moveTo(cx, cy - r * 0.42);
    ctx.lineTo(cx, cy + r * 0.08);
    ctx.stroke();

    ctx.fillStyle = '#DC2626';
    ctx.beginPath();
    ctx.arc(cx, cy + r * 0.42, w * 0.055, 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.restore();
}

function renderWhaleArchetype(
  ctx: CanvasRenderingContext2D,
  status: AgentStatus,
  frame: number,
  w: number,
  h: number,
  primary: string,
  secondary: string
) {
  ctx.save();
  const shakeX =
    status === AgentStatus.Error && frame < 6
      ? frame % 2 === 0
        ? -w * 0.05
        : w * 0.05
      : 0;
  const bobY =
    status === AgentStatus.Thinking
      ? Math.sin((frame / 15) * Math.PI * 2) * (h * 0.04)
      : status === AgentStatus.Working
      ? (frame % 3 === 0 ? -h * 0.035 : h * 0.02)
      : status === AgentStatus.Confirm
      ? -Math.abs(Math.sin((frame / 15) * Math.PI * 2)) * (h * 0.05)
      : 0;

  ctx.translate(shakeX, bobY);

  const tailSwing =
    status === AgentStatus.Working
      ? Math.sin((frame / 15) * Math.PI * 6) * (h * 0.12)
      : Math.sin((frame / 15) * Math.PI * 2) * (h * 0.05);

  ctx.fillStyle = status === AgentStatus.Error ? '#DC2626' : primary;
  ctx.beginPath();
  ctx.ellipse(w * 0.46, h * 0.58, w * 0.28, h * 0.21, 0, 0, Math.PI * 2);
  ctx.fill();

  ctx.strokeStyle = status === AgentStatus.Error ? '#B91C1C' : secondary;
  ctx.lineWidth = Math.max(1.6, w * 0.09);
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(w * 0.21, h * 0.58);
  ctx.lineTo(w * 0.1, h * 0.54 + tailSwing);
  ctx.moveTo(w * 0.1, h * 0.54 + tailSwing);
  ctx.lineTo(w * 0.06, h * 0.43 + tailSwing);
  ctx.moveTo(w * 0.1, h * 0.54 + tailSwing);
  ctx.lineTo(w * 0.07, h * 0.66 + tailSwing);
  ctx.stroke();

  ctx.fillStyle = 'rgba(255, 255, 255, 0.35)';
  ctx.beginPath();
  ctx.arc(w * 0.52, h * 0.65, w * 0.12, 0, Math.PI);
  ctx.fill();

  ctx.fillStyle = '#FFFFFF';
  if (status === AgentStatus.Completed) {
    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = Math.max(1.3, w * 0.07);
    ctx.beginPath();
    ctx.arc(w * 0.6, h * 0.54, w * 0.055, Math.PI * 1.1, Math.PI * 1.9);
    ctx.stroke();
  } else {
    ctx.beginPath();
    ctx.arc(
      w * 0.6,
      status === AgentStatus.Thinking ? h * 0.5 : h * 0.54,
      w * 0.05,
      0,
      Math.PI * 2
    );
    ctx.fill();
  }

  if (status === AgentStatus.Working) {
    const dropOffset = (frame % 5) * (w * 0.035);
    ctx.strokeStyle = secondary;
    ctx.lineWidth = Math.max(1.3, w * 0.07);
    ctx.beginPath();
    ctx.moveTo(w * 0.45, h * 0.34 - dropOffset * 0.5);
    ctx.lineTo(w * 0.39, h * 0.22 - dropOffset * 0.5);
    ctx.moveTo(w * 0.49, h * 0.34 - dropOffset * 0.5);
    ctx.lineTo(w * 0.55, h * 0.22 - dropOffset * 0.5);
    ctx.stroke();
  }

  ctx.restore();
  drawStatusOverlayBadge(ctx, status, frame, w, h);
}

function renderNekoArchetype(
  ctx: CanvasRenderingContext2D,
  status: AgentStatus,
  frame: number,
  w: number,
  h: number,
  primary: string,
  secondary: string
) {
  ctx.save();
  const shakeX =
    status === AgentStatus.Error && frame < 6
      ? frame % 2 === 0
        ? -w * 0.055
        : w * 0.055
      : 0;
  ctx.translate(shakeX, 0);

  const headColor = status === AgentStatus.Error ? '#DC2626' : primary;
  ctx.fillStyle = headColor;

  ctx.beginPath();
  ctx.moveTo(w * 0.22, h * 0.46);
  ctx.lineTo(w * 0.24, h * 0.18);
  ctx.lineTo(w * 0.42, h * 0.36);
  ctx.closePath();
  ctx.fill();

  ctx.beginPath();
  ctx.moveTo(w * 0.78, h * 0.46);
  ctx.lineTo(w * 0.76, h * 0.18);
  ctx.lineTo(w * 0.58, h * 0.36);
  ctx.closePath();
  ctx.fill();

  ctx.beginPath();
  ctx.roundRect(w * 0.2, h * 0.34, w * 0.6, h * 0.46, w * 0.16);
  ctx.fill();

  ctx.fillStyle = '#FFFFFF';
  ctx.strokeStyle = '#FFFFFF';
  ctx.lineWidth = Math.max(1.3, w * 0.07);
  const lookShiftX =
    status === AgentStatus.Thinking
      ? Math.sin((frame / 15) * Math.PI * 2) * (w * 0.04)
      : 0;
  const lookShiftY = status === AgentStatus.Thinking ? -h * 0.035 : 0;

  if (status === AgentStatus.Completed) {
    ctx.beginPath();
    ctx.arc(w * 0.38, h * 0.56, w * 0.055, Math.PI * 1.15, Math.PI * 1.85);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(w * 0.62, h * 0.56, w * 0.055, Math.PI * 1.15, Math.PI * 1.85);
    ctx.stroke();
  } else if (status === AgentStatus.Error) {
    ctx.beginPath();
    ctx.moveTo(w * 0.33, h * 0.51);
    ctx.lineTo(w * 0.41, h * 0.56);
    ctx.lineTo(w * 0.33, h * 0.61);
    ctx.moveTo(w * 0.67, h * 0.51);
    ctx.lineTo(w * 0.59, h * 0.56);
    ctx.lineTo(w * 0.67, h * 0.61);
    ctx.stroke();
  } else {
    ctx.beginPath();
    ctx.arc(w * 0.38 + lookShiftX, h * 0.55 + lookShiftY, w * 0.05, 0, Math.PI * 2);
    ctx.arc(w * 0.62 + lookShiftX, h * 0.55 + lookShiftY, w * 0.05, 0, Math.PI * 2);
    ctx.fill();
  }

  if (status === AgentStatus.Working) {
    const leftDown = frame % 4 < 2;
    ctx.fillStyle = secondary;
    ctx.beginPath();
    ctx.arc(w * 0.34, leftDown ? h * 0.87 : h * 0.79, w * 0.078, 0, Math.PI * 2);
    ctx.arc(w * 0.66, !leftDown ? h * 0.87 : h * 0.79, w * 0.078, 0, Math.PI * 2);
    ctx.fill();
  } else if (status === AgentStatus.Confirm) {
    const pawY = h * 0.48 + Math.sin((frame / 15) * Math.PI * 2) * (h * 0.06);
    ctx.fillStyle = secondary;
    ctx.beginPath();
    ctx.arc(w * 0.15, pawY, w * 0.078, 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.restore();
  drawStatusOverlayBadge(ctx, status, frame, w, h);
}

function renderKitsuneArchetype(
  ctx: CanvasRenderingContext2D,
  status: AgentStatus,
  frame: number,
  w: number,
  h: number,
  primary: string,
  secondary: string
) {
  ctx.save();
  const shakeX =
    status === AgentStatus.Error && frame < 6
      ? frame % 2 === 0
        ? -w * 0.05
        : w * 0.05
      : 0;
  const nodY = status === AgentStatus.Working ? (frame % 3 === 0 ? h * 0.03 : 0) : 0;
  ctx.translate(shakeX, nodY);

  ctx.fillStyle = status === AgentStatus.Error ? '#DC2626' : primary;

  ctx.beginPath();
  ctx.moveTo(w * 0.5, h * 0.84);
  ctx.lineTo(w * 0.18, h * 0.46);
  ctx.lineTo(w * 0.24, h * 0.14);
  ctx.lineTo(w * 0.42, h * 0.36);
  ctx.lineTo(w * 0.58, h * 0.36);
  ctx.lineTo(w * 0.76, h * 0.14);
  ctx.lineTo(w * 0.82, h * 0.46);
  ctx.closePath();
  ctx.fill();

  ctx.strokeStyle = '#FFFFFF';
  ctx.lineWidth = Math.max(1.5, w * 0.085);
  ctx.beginPath();
  ctx.moveTo(w * 0.31, h * 0.52);
  ctx.lineTo(w * 0.44, h * 0.57);
  ctx.moveTo(w * 0.69, h * 0.52);
  ctx.lineTo(w * 0.56, h * 0.57);
  ctx.stroke();

  if (status === AgentStatus.Working || status === AgentStatus.Thinking) {
    const scanX = w * (0.32 + 0.36 * ((frame % 15) / 14));
    ctx.fillStyle = secondary;
    ctx.beginPath();
    ctx.arc(scanX, h * 0.54, w * 0.055, 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.restore();
  drawStatusOverlayBadge(ctx, status, frame, w, h);
}

function renderCustomPixelArchetype(
  ctx: CanvasRenderingContext2D,
  status: AgentStatus,
  frame: number,
  w: number,
  h: number,
  pack: CharacterPack
) {
  const rows =
    pack.customBaseSprite && pack.customBaseSprite.length >= 8
      ? pack.customBaseSprite
      : [
          '....####....',
          '..########..',
          '.##########.',
          '.###+##+###.',
          '.###+##+###.',
          '.##########.',
          '..########..',
          '...######...',
          '....####....',
          '............',
          '............',
          '............',
        ];

  ctx.save();
  const shakeX =
    status === AgentStatus.Error && frame < 6
      ? frame % 2 === 0
        ? -w * 0.05
        : w * 0.05
      : 0;
  const bounceY =
    status === AgentStatus.Working
      ? frame % 2 === 0
        ? -h * 0.035
        : h * 0.02
      : status === AgentStatus.Thinking
      ? Math.sin((frame / 15) * Math.PI * 2) * (h * 0.035)
      : 0;

  ctx.translate(shakeX, bounceY);

  const gridH = rows.length;
  const gridW = rows[0]?.length || 12;
  const cellW = (w * 0.76) / gridW;
  const cellH = (h * 0.76) / gridH;
  const offsetX = w * 0.1;
  const offsetY = h * 0.16;

  for (let r = 0; r < gridH; r++) {
    const rowStr = rows[r];
    for (let c = 0; c < gridW; c++) {
      const ch = rowStr[c];
      if (ch === '#' || ch === '+') {
        ctx.fillStyle =
          ch === '+'
            ? status === AgentStatus.Error
              ? '#DC2626'
              : pack.secondaryColor
            : pack.primaryColor;
        ctx.fillRect(
          offsetX + c * cellW,
          offsetY + r * cellH,
          Math.ceil(cellW),
          Math.ceil(cellH)
        );
      }
    }
  }

  ctx.restore();
  drawStatusOverlayBadge(ctx, status, frame, w, h);
}

export const AgentSpriteCanvas: React.FC<AgentSpriteCanvasProps> = ({
  status,
  pack,
  size = 18,
  fixedFrame,
  monochrome = false,
  className = '',
}) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const dpr = typeof window !== 'undefined' ? window.devicePixelRatio || 2 : 2;
    const pixelW = Math.round(size * dpr);
    const pixelH = Math.round(size * dpr);
    canvas.width = pixelW;
    canvas.height = pixelH;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const primary = monochrome ? '#0F172A' : pack.primaryColor;
    const secondary = monochrome ? '#475569' : pack.secondaryColor;

    const drawFrame = (f: number) => {
      ctx.clearRect(0, 0, pixelW, pixelH);
      switch (pack.archetype) {
        case 'droplet':
          renderDropletArchetype(ctx, status, f, pixelW, pixelH, primary, secondary);
          break;
        case 'glyph':
          renderGlyphArchetype(ctx, status, f, pixelW, pixelH, primary);
          break;
        case 'neko':
          renderNekoArchetype(ctx, status, f, pixelW, pixelH, primary, secondary);
          break;
        case 'kitsune':
          renderKitsuneArchetype(ctx, status, f, pixelW, pixelH, primary, secondary);
          break;
        case 'custom_pixel':
          renderCustomPixelArchetype(ctx, status, f, pixelW, pixelH, pack);
          break;
        case 'whale':
        default:
          renderWhaleArchetype(ctx, status, f, pixelW, pixelH, primary, secondary);
          break;
      }
    };

    if (typeof fixedFrame === 'number') {
      drawFrame(((fixedFrame % 15) + 15) % 15);
      return;
    }

    drawFrame(globalFrame);
    const unsubscribe = subscribe15Fps(drawFrame);
    return unsubscribe;
  }, [status, pack, size, fixedFrame, monochrome]);

  const sizeClassMap: Record<number, string> = {
    14: 'w-3.5 h-3.5',
    16: 'w-4 h-4',
    18: 'w-[18px] h-[18px]',
    20: 'w-5 h-5',
    24: 'w-6 h-6',
    28: 'w-7 h-7',
    32: 'w-8 h-8',
    36: 'w-9 h-9',
  };
  const dimensionClass = sizeClassMap[size] || 'w-[18px] h-[18px]';

  return (
    <canvas
      ref={canvasRef}
      width={size * 2}
      height={size * 2}
      aria-label={`${pack.name} - ${status}`}
      className={`shrink-0 select-none ${dimensionClass} ${className}`}
    />
  );
};
