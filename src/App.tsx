import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  ArrowUpRight,
  Bell,
  BellOff,
  Check,
  ChevronDown,
  ChevronRight,
  Copy,
  Download,
  FileCode2,
  FolderArchive,
  KeyRound,
  Plus,
  RefreshCw,
  Settings,
  Terminal,
  Trash2,
  Volume2,
  X,
} from 'lucide-react';
import { AgentSpurLogo } from './components/AgentSpurLogo';
import { buildMacOSZipBlob, ZipFileEntry } from './utils/zipBuilder';

import packageSwiftRaw from '../Package.swift?raw';
import buildDmgShRaw from '../build_dmg.sh?raw';
import doubleClickCmdRaw from '../双击打包DMG.command?raw';
import makefileRaw from '../Makefile?raw';
import readmeRaw from '../README.md?raw';
import infoPlistRaw from '../Resources/Info.plist?raw';
import samplePackJsonRaw from '../Resources/sample-deepseek-pack.json?raw';
import appEntrySwiftRaw from '../Sources/AgentSpur/AgentSpurApp.swift?raw';
import pricingEngineSwiftRaw from '../Sources/AgentSpur/DeepSeekPricingEngine.swift?raw';
import modelsSwiftRaw from '../Sources/AgentSpur/Models.swift?raw';
import dbReaderSwiftRaw from '../Sources/AgentSpur/OpenCodeDBReader.swift?raw';
import spriteRendererSwiftRaw from '../Sources/AgentSpur/SpriteRenderer.swift?raw';
import terminalBridgeSwiftRaw from '../Sources/AgentSpur/TerminalBridge.swift?raw';
import popoverViewsSwiftRaw from '../Sources/AgentSpur/PopoverViews.swift?raw';

interface SourceFileItem {
  relPath: string;
  label: string;
  content: string;
  executable?: boolean;
}

const NATIVE_FILES: SourceFileItem[] = [
  {
    relPath: 'build_dmg.sh',
    label: 'build_dmg.sh (一键生成 DMG)',
    content: buildDmgShRaw,
    executable: true,
  },
  {
    relPath: '双击打包DMG.command',
    label: '双击打包DMG.command',
    content: doubleClickCmdRaw,
    executable: true,
  },
  {
    relPath: 'Package.swift',
    label: 'Package.swift',
    content: packageSwiftRaw,
  },
  {
    relPath: 'Sources/AgentSpur/PopoverViews.swift',
    label: 'Sources/AgentSpur/PopoverViews.swift (极简重构 UI)',
    content: popoverViewsSwiftRaw,
  },
  {
    relPath: 'Sources/AgentSpur/AgentSpurApp.swift',
    label: 'Sources/AgentSpur/AgentSpurApp.swift (多Key + 原生提示音)',
    content: appEntrySwiftRaw,
  },
  {
    relPath: 'Sources/AgentSpur/OpenCodeDBReader.swift',
    label: 'Sources/AgentSpur/OpenCodeDBReader.swift (O(1) 分组缓存 + 只读引擎)',
    content: dbReaderSwiftRaw,
  },
  {
    relPath: 'Sources/AgentSpur/SpriteRenderer.swift',
    label: 'Sources/AgentSpur/SpriteRenderer.swift (Retina .fit 居中徽标)',
    content: spriteRendererSwiftRaw,
  },
  {
    relPath: 'Sources/AgentSpur/DeepSeekPricingEngine.swift',
    label: 'Sources/AgentSpur/DeepSeekPricingEngine.swift (汇率 + 忙闲时精算)',
    content: pricingEngineSwiftRaw,
  },
  {
    relPath: 'Sources/AgentSpur/TerminalBridge.swift',
    label: 'Sources/AgentSpur/TerminalBridge.swift (真实终端联动)',
    content: terminalBridgeSwiftRaw,
  },
  {
    relPath: 'Sources/AgentSpur/Models.swift',
    label: 'Sources/AgentSpur/Models.swift',
    content: modelsSwiftRaw,
  },
  {
    relPath: 'Resources/Info.plist',
    label: 'Resources/Info.plist',
    content: infoPlistRaw,
  },
  {
    relPath: 'Resources/sample-deepseek-pack.json',
    label: 'Resources/sample-deepseek-pack.json',
    content: samplePackJsonRaw,
  },
  {
    relPath: 'Makefile',
    label: 'Makefile',
    content: makefileRaw,
  },
  {
    relPath: 'README.md',
    label: 'README.md',
    content: readmeRaw,
  },
];

type CurrencyMode = 'CNY' | 'USD';
type SessionFilter = 'all' | 'pending' | 'running' | 'completed';
type SessionStatus = 'working' | 'thinking' | 'confirm' | 'completed' | 'error';

interface PreviewSubAgent {
  id: string;
  role: string;
  title: string;
  costCny: number;
  cachePct: number;
  activeSec?: number;
}

interface PreviewMasterSession {
  id: string;
  keyId: string;
  title: string;
  status: SessionStatus;
  costCny: number;
  ownCostCny: number;
  cachePct: number;
  requests: number;
  terminalLabel: string;
  directory: string;
  elapsedSec: number;
  focused?: boolean;
  subAgents: PreviewSubAgent[];
}

interface PreviewKeyScope {
  id: string;
  label: string;
  shortLabel: string;
  autoSource?: string;
  totalCostCny: number;
  peakCostCny: number;
  offPeakCostCny: number;
  cacheSavedCny: number;
  offPeakSavedCny: number;
  cacheHitPct: number;
  hitTokensLabel: string;
  missTokensLabel: string;
  outputTokensLabel: string;
  requestCount: number;
  opencodeStaticUsd: number;
  hourlyReqs: number[];
  hourlyCostsCny: number[];
}

const FX_USD_TO_CNY = 6.6682;

const PREVIEW_SCOPES: PreviewKeyScope[] = [
  {
    id: '__ALL__',
    label: '全部 Key (汇总)',
    shortLabel: '全部 Key',
    totalCostCny: 38.9416,
    peakCostCny: 32.67,
    offPeakCostCny: 6.27,
    cacheSavedCny: 510.39,
    offPeakSavedCny: 6.27,
    cacheHitPct: 97.3,
    hitTokensLabel: '305.99M',
    missTokensLabel: '8.56M',
    outputTokensLabel: '1.98M',
    requestCount: 3271,
    opencodeStaticUsd: 3.391,
    hourlyReqs: [380, 145, 18, 0, 0, 0, 0, 12, 85, 420, 395, 790, 210, 42, 435, 185, 310, 260, 190, 140, 220, 435, 160, 45],
    hourlyCostsCny: [1.12, 0.44, 0.06, 0, 0, 0, 0, 0.05, 0.32, 3.85, 3.62, 7.45, 0.82, 0.19, 4.18, 1.72, 2.94, 2.41, 0.76, 0.58, 0.92, 1.2, 0.64, 0.18],
  },
  {
    id: 'key-main',
    label: 'DeepSeek 官方 (sk-***01)',
    shortLabel: 'DeepSeek 官方',
    autoSource: 'auth.json',
    totalCostCny: 31.482,
    peakCostCny: 26.9,
    offPeakCostCny: 4.582,
    cacheSavedCny: 428.15,
    offPeakSavedCny: 4.58,
    cacheHitPct: 97.6,
    hitTokensLabel: '254.10M',
    missTokensLabel: '6.25M',
    outputTokensLabel: '1.56M',
    requestCount: 2640,
    opencodeStaticUsd: 2.742,
    hourlyReqs: [320, 120, 18, 0, 0, 0, 0, 0, 60, 360, 330, 680, 170, 20, 365, 150, 260, 210, 140, 95, 160, 310, 110, 25],
    hourlyCostsCny: [0.95, 0.36, 0.06, 0, 0, 0, 0, 0, 0.24, 3.31, 3.04, 6.42, 0.68, 0.09, 3.52, 1.41, 2.46, 1.98, 0.56, 0.39, 0.68, 0.86, 0.44, 0.1],
  },
  {
    id: 'key-sub',
    label: '个人备用Key (sk-***89)',
    shortLabel: '备用Key (sk-***89)',
    autoSource: 'opencode.json',
    totalCostCny: 7.4596,
    peakCostCny: 5.77,
    offPeakCostCny: 1.6896,
    cacheSavedCny: 82.24,
    offPeakSavedCny: 1.69,
    cacheHitPct: 95.7,
    hitTokensLabel: '51.89M',
    missTokensLabel: '2.31M',
    outputTokensLabel: '420.0K',
    requestCount: 631,
    opencodeStaticUsd: 0.649,
    hourlyReqs: [60, 25, 0, 0, 0, 0, 0, 12, 25, 60, 65, 110, 40, 22, 70, 35, 50, 50, 50, 45, 60, 125, 50, 20],
    hourlyCostsCny: [0.17, 0.08, 0, 0, 0, 0, 0, 0.05, 0.08, 0.54, 0.58, 1.03, 0.14, 0.1, 0.66, 0.31, 0.48, 0.43, 0.2, 0.19, 0.24, 0.34, 0.2, 0.08],
  },
];

const PREVIEW_SESSIONS: PreviewMasterSession[] = [
  {
    id: 'ses-oom',
    keyId: 'key-main',
    title: 'OOM策略：可观测性先行渐进落地',
    status: 'working',
    costCny: 0.6912,
    ownCostCny: 0.5312,
    cachePct: 96,
    requests: 78,
    terminalLabel: 'Terminal #1 · oc-lofa',
    directory: '~/ai-setup/opencode-lofa',
    elapsedSec: 33,
    focused: true,
    subAgents: [
      {
        id: 'sub-1',
        role: '@dev',
        title: '修 subagent-watchdog 零产出与内存采样阈值',
        costCny: 0.112,
        cachePct: 96,
        activeSec: 19,
      },
      {
        id: 'sub-2',
        role: '@explore',
        title: '检索 Darwin Mach RSS 指标采集路径',
        costCny: 0.048,
        cachePct: 95,
      },
    ],
  },
  {
    id: 'ses-pr33',
    keyId: 'key-sub',
    title: 'opencode 重启后处理 #33 与 #68 回归验收',
    status: 'thinking',
    costCny: 0.4218,
    ownCostCny: 0.284,
    cachePct: 97,
    requests: 44,
    terminalLabel: 'tmux · oc-opencode-master',
    directory: '~/ai-setup/opencode-master',
    elapsedSec: 12,
    subAgents: [
      {
        id: 'sub-3',
        role: '@dev',
        title: '补跑 #68/#69 独立单测套件冻结校验',
        costCny: 0.1378,
        cachePct: 97,
        activeSec: 8,
      },
    ],
  },
  {
    id: 'ses-done-1',
    keyId: 'key-main',
    title: 'SQLite rowid 二分查找替代全表扫描',
    status: 'completed',
    costCny: 1.184,
    ownCostCny: 0.92,
    cachePct: 98,
    requests: 136,
    terminalLabel: 'iTerm2 #2 · AgentSpur',
    directory: '~/Downloads/AgentSpur',
    elapsedSec: 420,
    subAgents: [
      {
        id: 'sub-4',
        role: '@explore',
        title: '审计 message_session_idx 执行计划',
        costCny: 0.264,
        cachePct: 98,
      },
    ],
  },
  {
    id: 'ses-done-2',
    keyId: 'key-sub',
    title: '同步 DeepSeek 官方 CSV 忙闲时单价对账',
    status: 'completed',
    costCny: 0.852,
    ownCostCny: 0.852,
    cachePct: 97,
    requests: 92,
    terminalLabel: 'Terminal #2 · billing',
    directory: '~/ai-setup/billing-audit',
    elapsedSec: 910,
    subAgents: [],
  },
];

const ROLE_PACK_OPTIONS = [
  { id: 'pack-whale', label: '🐳 深海小鲸' },
  { id: 'pack-droplet', label: '💧 Gin · 灵动微光' },
  { id: 'pack-neko', label: '🐱 晴空像素猫' },
  { id: 'pack-kitsune', label: '🦊 折纸灵狐' },
];

const PREVIEW_CONSOLES = [
  { id: 'win-1', indexLabel: '01 · Terminal #1 · AgentSpur — zsh', shortSummary: 'Terminal · AgentSpur', active: true },
  { id: 'win-2', indexLabel: '02 · Terminal #2 · agent-memory — tmux new', shortSummary: 'Terminal · agent-memory', active: false },
  { id: 'win-3', indexLabel: '03 · iTerm2 #1 · billing-audit — opencode', shortSummary: 'iTerm2 · billing-audit', active: false },
  { id: 'win-4', indexLabel: '04 · iTerm2 #2 · subagent-watchdog — tail -f', shortSummary: 'iTerm2 · watchdog', active: false },
  { id: 'win-5', indexLabel: '05 · Terminal #3 · deepseek-router — cargo run', shortSummary: 'Terminal · router', active: false },
  { id: 'win-6', indexLabel: '06 · iTerm2 #3 · eval-bench — python runner.py', shortSummary: 'iTerm2 · eval-bench', active: false },
  { id: 'win-7', indexLabel: '07 · Terminal #4 · docs-portal — npm run dev', shortSummary: 'Terminal · docs-portal', active: false },
];

function RolePackSpriteIcon({
  packId,
  status,
  size = 18,
}: {
  packId: string;
  status: SessionStatus;
  size?: number;
}) {
  const isError = status === 'error';
  const isConfirm = status === 'confirm';
  const isCompleted = status === 'completed';

  if (packId === 'pack-whale') {
    const bodyFill = isError ? '#E13D48' : isConfirm ? '#D97706' : '#0284C7';
    const spoutFill = isError ? '#F87171' : '#38BDF8';
    return (
      <svg
        width={size}
        height={size}
        viewBox="0 0 18 18"
        fill="none"
        className="aspect-square shrink-0"
        aria-hidden="true"
      >
        <circle cx="5.35" cy="2.9" r="0.9" fill={spoutFill} />
        <circle cx="7.8" cy="3.2" r="0.75" fill={spoutFill} />
        <path
          d="M1.8 10.6 C1.7 6.2 4.1 4.7 7.4 4.8 C10.3 4.9 11.6 8.8 12.6 10.1 C13.6 8.4 14.9 6.4 16.1 6.5 C16.0 8.3 15.1 9.6 14.4 10.3 C15.3 10.9 16.3 11.9 16.2 13.2 C14.9 13.4 13.4 12.7 12.1 12.3 C10.2 15.3 2.2 14.9 1.8 10.6 Z"
          fill={bodyFill}
        />
        <path
          d="M2.2 11.45 Q6.2 11.75 10.4 13.45 C8.5 14.8 3.2 14.5 2.2 11.45 Z"
          fill="#FFFFFF"
          fillOpacity="0.82"
        />
        <circle cx="5.55" cy="9.05" r="1.25" fill="#FFFFFF" />
        <circle cx="5.65" cy="9.05" r="0.68" fill="#0F1E3D" />
      </svg>
    );
  }

  if (packId === 'pack-neko') {
    const primary = isError ? '#E13D48' : '#0369A1';
    const eye = isError ? '#FCA5A5' : '#38BDF8';
    return (
      <svg width={size} height={size} viewBox="0 0 18 18" fill="none" className="aspect-square shrink-0" aria-hidden="true">
        <rect x="4.2" y="3.8" width="2.5" height="2.5" rx="0.5" fill={primary} />
        <rect x="11.3" y="3.8" width="2.5" height="2.5" rx="0.5" fill={primary} />
        <rect x="4.2" y="6.0" width="9.6" height="7.8" rx="1.8" fill={primary} />
        <rect x="6.1" y="8.8" width="1.8" height="1.8" rx="0.4" fill={eye} />
        <rect x="10.1" y="8.8" width="1.8" height="1.8" rx="0.4" fill={eye} />
      </svg>
    );
  }

  if (packId === 'pack-kitsune') {
    const fill = isConfirm ? '#F59E0B' : isError ? '#E13D48' : '#0284C7';
    return (
      <svg width={size} height={size} viewBox="0 0 18 18" fill="none" className="aspect-square shrink-0" aria-hidden="true">
        <path d="M9 14.6 L14.4 4.8 L10.9 7.2 L7.1 7.2 L3.6 4.8 Z" fill={fill} />
        <circle cx="7.1" cy="9.6" r="0.85" fill="#FFFFFF" />
        <circle cx="10.9" cy="9.6" r="0.85" fill="#FFFFFF" />
      </svg>
    );
  }

  const dropletFill = isError
    ? '#DC2626'
    : isConfirm
      ? '#D97706'
      : isCompleted
        ? '#059669'
        : '#0284C7';
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none" className="aspect-square shrink-0" aria-hidden="true">
      <circle cx="9" cy="9.2" r="6.3" stroke={dropletFill} strokeOpacity="0.24" strokeWidth="1.1" />
      <path
        d="M9 4.0 C10.9 6.3 12.65 8.35 12.65 10.05 C12.65 12.07 11.02 13.65 9 13.65 C6.98 13.65 5.35 12.07 5.35 10.05 C5.35 8.35 7.1 6.3 9 4.0 Z"
        fill={dropletFill}
      />
      <circle cx="7.85" cy="9.55" r="0.9" fill="#FFFFFF" fillOpacity="0.92" />
    </svg>
  );
}

function maskApiKey(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.length < 6) return trimmed;
  return `${trimmed.slice(0, 3)}***${trimmed.slice(-2)}`;
}

function formatMoneyDisplay(cny: number, mode: CurrencyMode, highPrecision = false): string {
  if (mode === 'CNY') {
    const digits = highPrecision || (cny > 0 && cny < 0.1) ? 4 : 2;
    return `¥${cny.toFixed(digits)}`;
  }
  const usd = cny / FX_USD_TO_CNY;
  const digits = highPrecision || (usd > 0 && usd < 0.1) ? 4 : 2;
  return `$${usd.toFixed(digits)}`;
}

function playNativeGlassChime() {
  try {
    const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    if (!AudioCtx) return;
    const ctx = new AudioCtx();
    const now = ctx.currentTime;

    const osc1 = ctx.createOscillator();
    const osc2 = ctx.createOscillator();
    const gain = ctx.createGain();

    osc1.type = 'sine';
    osc2.type = 'triangle';
    osc1.frequency.setValueAtTime(987.77, now); // B5
    osc1.frequency.exponentialRampToValueAtTime(1318.51, now + 0.09); // E6
    osc2.frequency.setValueAtTime(1975.53, now);

    gain.gain.setValueAtTime(0.001, now);
    gain.gain.exponentialRampToValueAtTime(0.14, now + 0.015);
    gain.gain.exponentialRampToValueAtTime(0.0008, now + 0.42);

    osc1.connect(gain);
    osc2.connect(gain);
    gain.connect(ctx.destination);

    osc1.start(now);
    osc2.start(now);
    osc1.stop(now + 0.44);
    osc2.stop(now + 0.44);
  } catch {
    // Ignore audio context restrictions
  }
}

export default function App() {
  const [selectedPath, setSelectedPath] = useState<string>('Sources/AgentSpur/PopoverViews.swift');
  const [copiedCmd, setCopiedCmd] = useState<boolean>(false);
  const [copiedFile, setCopiedFile] = useState<boolean>(false);

  // Shared Header & Interactive Native Popover Preview State
  const [keyScopes, setKeyScopes] = useState<PreviewKeyScope[]>(PREVIEW_SCOPES);
  const [selectedKeyId, setSelectedKeyId] = useState<string>('__ALL__');
  const [currencyMode, setCurrencyMode] = useState<CurrencyMode>('CNY');
  const [keyMenuOpen, setKeyMenuOpen] = useState<boolean>(false);
  const [settingsMenuOpen, setSettingsMenuOpen] = useState<boolean>(false);
  const [popoverKeyMenuOpen, setPopoverKeyMenuOpen] = useState<boolean>(false);
  const [popoverGearOpen, setPopoverGearOpen] = useState<boolean>(false);
  const [popoverConsoleSubmenuOpen, setPopoverConsoleSubmenuOpen] = useState<boolean>(false);
  const [selectedConsoleId, setSelectedConsoleId] = useState<string | null>(null);
  const [packMenuOpen, setPackMenuOpen] = useState<boolean>(false);

  // In-Popover API-Key Manager Sheet State (Renders Inside NSPopover, Never Behind Windows)
  const [apiKeySheetOpen, setApiKeySheetOpen] = useState<boolean>(false);
  const [formKeyName, setFormKeyName] = useState<string>('');
  const [formKeySecret, setFormKeySecret] = useState<string>('');
  const [formKeyDir, setFormKeyDir] = useState<string>('');

  const [liveTickSec, setLiveTickSec] = useState<number>(33);
  const [isRefreshing, setIsRefreshing] = useState<boolean>(false);
  const [autoFocusTerminal, setAutoFocusTerminal] = useState<boolean>(true);
  const [menuBarMode, setMenuBarMode] = useState<'iconOnly' | 'compactAmount' | 'fullStatus'>('iconOnly');
  const [floatingPillEnabled, setFloatingPillEnabled] = useState<boolean>(true);
  const [launchAtLogin, setLaunchAtLogin] = useState<boolean>(true);
  const [notificationsMuted, setNotificationsMuted] = useState<boolean>(false);
  const [selectedPackId, setSelectedPackId] = useState<string>('pack-whale');
  const [sessionFilter, setSessionFilter] = useState<SessionFilter>('all');
  // Sub-agents collapsed by default (empty set!)
  const [expandedSessionIds, setExpandedSessionIds] = useState<Set<string>>(() => new Set());
  const [hoveredBarHour, setHoveredBarHour] = useState<number | null>(null);
  const [showCostTooltip, setShowCostTooltip] = useState<boolean>(false);
  const [toastBanner, setToastBanner] = useState<string | null>(null);
  const [isPopoverShown, setIsPopoverShown] = useState<boolean>(false);

  const headerControlsRef = useRef<HTMLDivElement | null>(null);
  const keyNameInputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    const rafId = window.requestAnimationFrame(() => {
      setIsPopoverShown(true);
    });
    const timer = window.setInterval(() => {
      setLiveTickSec((prev) => prev + 1);
    }, 1000);
    return () => {
      window.cancelAnimationFrame(rafId);
      window.clearInterval(timer);
    };
  }, []);

  useEffect(() => {
    const onDocClick = (e: MouseEvent) => {
      if (headerControlsRef.current && !headerControlsRef.current.contains(e.target as Node)) {
        setKeyMenuOpen(false);
        setSettingsMenuOpen(false);
      }
    };
    const onKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'r') {
        e.preventDefault();
        triggerRefresh();
      }
      if (e.key === 'Escape') {
        if (apiKeySheetOpen) {
          setApiKeySheetOpen(false);
        } else {
          setIsPopoverShown(false);
        }
      }
    };
    document.addEventListener('mousedown', onDocClick);
    window.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('mousedown', onDocClick);
      window.removeEventListener('keydown', onKeyDown);
    };
  }, [apiKeySheetOpen]);

  const selectedFile = useMemo(
    () => NATIVE_FILES.find((f) => f.relPath === selectedPath) ?? NATIVE_FILES[0],
    [selectedPath]
  );

  const activeScope = useMemo(
    () => keyScopes.find((s) => s.id === selectedKeyId) ?? keyScopes[0],
    [keyScopes, selectedKeyId]
  );

  const openApiKeyManagerSheet = () => {
    setIsPopoverShown(true);
    setKeyMenuOpen(false);
    setSettingsMenuOpen(false);
    setPopoverKeyMenuOpen(false);
    setPopoverGearOpen(false);
    setFormKeyName('');
    setFormKeySecret('');
    setFormKeyDir('');
    setApiKeySheetOpen(true);
    window.setTimeout(() => {
      keyNameInputRef.current?.focus();
    }, 60);
  };

  const handleSaveApiKeyProfile = (e: React.FormEvent) => {
    e.preventDefault();
    const cleanName = formKeyName.trim() || `备用Key-${keyScopes.length}`;
    const masked = formKeySecret.trim() ? maskApiKey(formKeySecret) : '';
    const displayLabel = masked ? `${cleanName} (${masked})` : cleanName;

    const existingIdx = keyScopes.findIndex(
      (s) => s.id !== '__ALL__' && (s.shortLabel.startsWith(cleanName) || s.label.startsWith(cleanName))
    );
    if (existingIdx >= 0) {
      const targetId = keyScopes[existingIdx].id;
      setKeyScopes((prev) =>
        prev.map((item, idx) =>
          idx === existingIdx
            ? { ...item, label: displayLabel, shortLabel: displayLabel }
            : item
        )
      );
      setSelectedKeyId(targetId);
    } else {
      const newId = `key-${Date.now().toString().slice(-4)}`;
      const newScope: PreviewKeyScope = {
        id: newId,
        label: displayLabel,
        shortLabel: displayLabel,
        totalCostCny: 0,
        peakCostCny: 0,
        offPeakCostCny: 0,
        cacheSavedCny: 0,
        offPeakSavedCny: 0,
        cacheHitPct: 0,
        hitTokensLabel: '0',
        missTokensLabel: '0',
        outputTokensLabel: '0',
        requestCount: 0,
        opencodeStaticUsd: 0,
        hourlyReqs: Array(24).fill(0),
        hourlyCostsCny: Array(24).fill(0),
      };
      setKeyScopes((prev) => [...prev, newScope]);
      setSelectedKeyId(newId);
    }
    setApiKeySheetOpen(false);
    triggerToast(`已保存并切换至分组：${displayLabel}`);
  };

  const handleDeleteApiKeyProfile = (id: string) => {
    const nonAll = keyScopes.filter((s) => s.id !== '__ALL__');
    if (nonAll.length <= 1) return;
    setKeyScopes((prev) => prev.filter((s) => s.id !== id));
    if (selectedKeyId === id) {
      setSelectedKeyId('__ALL__');
    }
    triggerToast('已移除该 API-Key 分组');
  };

  const scopedSessions = useMemo(() => {
    const base =
      selectedKeyId === '__ALL__'
        ? PREVIEW_SESSIONS
        : PREVIEW_SESSIONS.filter((s) => s.keyId === selectedKeyId);
    return base;
  }, [selectedKeyId]);

  const filteredSessions = useMemo(() => {
    if (sessionFilter === 'pending') return scopedSessions.filter((s) => s.status === 'confirm');
    if (sessionFilter === 'running')
      return scopedSessions.filter((s) => s.status === 'working' || s.status === 'thinking');
    if (sessionFilter === 'completed') return scopedSessions.filter((s) => s.status === 'completed');
    return scopedSessions;
  }, [scopedSessions, sessionFilter]);

  const activePack = useMemo(
    () => ROLE_PACK_OPTIONS.find((p) => p.id === selectedPackId) ?? ROLE_PACK_OPTIONS[0],
    [selectedPackId]
  );

  const triggerToast = (msg: string) => {
    setToastBanner(msg);
    window.setTimeout(() => {
      setToastBanner((curr) => (curr === msg ? null : curr));
    }, 2400);
  };

  const triggerRefresh = () => {
    setIsRefreshing(true);
    triggerToast('已同步实时汇率 ($1 = ¥6.6682) 与今日预聚合账单');
    window.setTimeout(() => setIsRefreshing(false), 480);
  };

  const handleToggleMute = () => {
    setNotificationsMuted((prev) => {
      const next = !prev;
      if (!next) {
        playNativeGlassChime();
        triggerToast('已开启系统提示音与前台通知横幅');
      } else {
        triggerToast('已静音任务通知');
      }
      return next;
    });
  };

  const handleTestNotification = () => {
    setNotificationsMuted(false);
    playNativeGlassChime();
    triggerToast('🔔 AgentSpur · 任务已完成（Glass 原生提示音已触发）');
    setSettingsMenuOpen(false);
    setPopoverGearOpen(false);
  };

  const toggleExpandSession = (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    setExpandedSessionIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  };

  const handleDownloadNativeZip = () => {
    const entries: ZipFileEntry[] = NATIVE_FILES.map((f) => ({
      path: `AgentSpur/${f.relPath}`,
      content: f.content,
      executable: f.executable,
    }));
    const blob = buildMacOSZipBlob(entries);
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'AgentSpur-macOS-Native.zip';
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleCopyCommand = async () => {
    try {
      await navigator.clipboard.writeText('chmod +x build_dmg.sh && ./build_dmg.sh');
      setCopiedCmd(true);
      window.setTimeout(() => setCopiedCmd(false), 1600);
    } catch {
      // Ignore clipboard fallback
    }
  };

  const handleCopyCurrentFile = async () => {
    try {
      await navigator.clipboard.writeText(selectedFile.content);
      setCopiedFile(true);
      window.setTimeout(() => setCopiedFile(false), 1600);
    } catch {
      // Ignore clipboard fallback
    }
  };

  const maxHourlyReq = Math.max(1, ...activeScope.hourlyReqs);
  const runningCount = scopedSessions.filter((s) => s.status === 'working' || s.status === 'thinking').length;
  const pendingCount = scopedSessions.filter((s) => s.status === 'confirm').length;
  const completedCount = scopedSessions.filter((s) => s.status === 'completed').length;

  return (
    <div className="min-h-screen w-full bg-[#F8FAFC] text-slate-900">
      {/* Refactored Clean Top Header: Pure Identity + Running Capsule on Left, Uniform h-8 Rounded-Full Controls on Right */}
      <header className="sticky top-0 z-40 border-b border-slate-200/80 bg-white/85 backdrop-blur-xl">
        <div className="mx-auto flex h-14 max-w-[1180px] items-center justify-between gap-4 px-6">
          {/* Left Identity Zone: ONLY [1:1 Logo] AgentSpur + Clean Running Status Capsule */}
          <div className="inline-flex items-center gap-3 min-w-0">
            <AgentSpurLogo size={24} className="aspect-square shrink-0" />
            <span className="text-[15px] font-semibold tracking-tight text-slate-900">
              AgentSpur
            </span>
            <span className="inline-flex h-6 items-center gap-1.5 rounded-full border border-sky-200/90 bg-sky-50/90 px-2.5 text-xs font-medium text-sky-700 tabular-nums shrink-0">
              <span className="h-1.5 w-1.5 rounded-full bg-sky-500 animate-pulse shrink-0" />
              <span>正在工作 {liveTickSec}s</span>
            </span>
          </div>

          {/* Right Control Zone: Uniform h-8 rounded-full inline-flex Native Capsule Controls */}
          <div ref={headerControlsRef} className="inline-flex items-center gap-2 shrink-0">
            {/* Global API-Key & Currency Capsule Selector */}
            <div className="relative inline-flex">
              <button
                type="button"
                onClick={() => {
                  setKeyMenuOpen((v) => !v);
                  setSettingsMenuOpen(false);
                }}
                className="inline-flex h-8 items-center gap-1.5 rounded-full border border-slate-200/90 bg-white px-3 text-xs font-medium text-slate-700 shadow-[0_1px_2px_rgba(15,23,42,0.03)] hover:border-slate-300 hover:bg-slate-50/90 transition-colors cursor-pointer whitespace-nowrap"
              >
                <KeyRound className="h-3.5 w-3.5 text-sky-600 shrink-0" />
                <span>{activeScope.shortLabel}</span>
                <span className="text-slate-300" aria-hidden="true">·</span>
                <span className="font-mono text-slate-600">{currencyMode === 'CNY' ? '¥' : '$'}</span>
                <ChevronDown className="h-3.5 w-3.5 text-slate-400 shrink-0" />
              </button>

              {keyMenuOpen && (
                <div className="absolute right-0 top-10 z-50 w-64 rounded-xl border border-slate-200/90 bg-white p-1.5 shadow-lg">
                  <div className="px-2.5 py-1 text-[11px] font-medium text-slate-400">
                    切换 API-Key 统计分组 (&lt;1ms 内存过滤)
                  </div>
                  {keyScopes.map((sc) => {
                    const selected = sc.id === selectedKeyId;
                    return (
                      <button
                        key={sc.id}
                        type="button"
                        onClick={() => {
                          setSelectedKeyId(sc.id);
                          setKeyMenuOpen(false);
                        }}
                        className={`flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 text-xs transition-colors cursor-pointer ${
                          selected
                            ? 'bg-sky-50 font-semibold text-sky-800'
                            : 'text-slate-700 hover:bg-slate-50'
                        }`}
                      >
                        <span className="truncate">{sc.label}</span>
                        <span className="font-mono text-[11px] text-slate-500 tabular-nums">
                          {formatMoneyDisplay(sc.totalCostCny, currencyMode)}
                        </span>
                      </button>
                    );
                  })}
                  <div className="my-1 border-t border-slate-100" />
                  <div className="px-2.5 py-1 text-[11px] font-medium text-slate-400">
                    计费展示币种
                  </div>
                  <div className="grid grid-cols-2 gap-1 px-1 pb-1">
                    {(['CNY', 'USD'] as CurrencyMode[]).map((m) => (
                      <button
                        key={m}
                        type="button"
                        onClick={() => {
                          setCurrencyMode(m);
                          setKeyMenuOpen(false);
                        }}
                        className={`h-7 rounded-lg text-xs font-mono font-medium transition-colors cursor-pointer ${
                          currencyMode === m
                            ? 'bg-slate-900 text-white'
                            : 'bg-slate-100/80 text-slate-600 hover:bg-slate-200/70'
                        }`}
                      >
                        {m === 'CNY' ? '¥ CNY' : '$ USD'}
                      </button>
                    ))}
                  </div>
                  <div className="my-1 border-t border-slate-100" />
                  <button
                    type="button"
                    onClick={openApiKeyManagerSheet}
                    className="flex w-full items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-xs font-medium text-sky-700 hover:bg-sky-50 cursor-pointer"
                  >
                    <Plus className="h-3.5 w-3.5 shrink-0" />
                    <span>添加 / 管理多 API-Key…</span>
                  </button>
                </div>
              )}
            </div>

            {/* Refresh ⌘R Capsule Button */}
            <button
              type="button"
              onClick={triggerRefresh}
              title="立即刷新实时汇率与今日统计 (⌘R)"
              className="inline-flex h-8 items-center justify-center gap-1.5 rounded-full border border-slate-200/90 bg-white px-3 text-xs font-medium font-mono text-slate-700 shadow-[0_1px_2px_rgba(15,23,42,0.03)] hover:border-slate-300 hover:bg-slate-50/90 transition-colors cursor-pointer whitespace-nowrap"
            >
              <RefreshCw
                className={`h-3.5 w-3.5 text-slate-500 shrink-0 ${isRefreshing ? 'animate-spin text-sky-600' : ''}`}
              />
              <span>⌘R</span>
            </button>

            {/* Gear Settings Capsule Button */}
            <div className="relative inline-flex">
              <button
                type="button"
                onClick={() => {
                  setSettingsMenuOpen((v) => !v);
                  setKeyMenuOpen(false);
                }}
                title="设置与通知自检"
                className="inline-flex h-8 w-8 items-center justify-center rounded-full border border-slate-200/90 bg-white text-slate-600 shadow-[0_1px_2px_rgba(15,23,42,0.03)] hover:border-slate-300 hover:bg-slate-50/90 hover:text-slate-900 transition-colors cursor-pointer"
              >
                <Settings className="h-3.5 w-3.5 shrink-0" />
              </button>

              {settingsMenuOpen && (
                <div className="absolute right-0 top-10 z-50 w-56 rounded-xl border border-slate-200/90 bg-white p-1.5 shadow-lg text-xs">
                  <button
                    type="button"
                    onClick={() => setAutoFocusTerminal((v) => !v)}
                    className="flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 text-slate-700 hover:bg-slate-50 cursor-pointer"
                  >
                    <span>终端自动聚焦高亮</span>
                    <span className="font-mono text-sky-600">{autoFocusTerminal ? '✓' : ''}</span>
                  </button>
                  <button
                    type="button"
                    onClick={handleTestNotification}
                    className="flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-slate-700 hover:bg-slate-50 cursor-pointer"
                  >
                    <Volume2 className="h-3.5 w-3.5 text-sky-600 shrink-0" />
                    <span>测试系统提示音与横幅</span>
                  </button>
                </div>
              )}
            </div>

            {/* Primary Download .zip Capsule Button */}
            <button
              type="button"
              onClick={handleDownloadNativeZip}
              className="inline-flex h-8 items-center justify-center gap-1.5 rounded-full bg-slate-900 px-3.5 text-xs font-medium text-white shadow-[0_1px_2px_rgba(15,23,42,0.08)] hover:bg-slate-800 transition-colors cursor-pointer whitespace-nowrap shrink-0"
            >
              <FolderArchive className="h-3.5 w-3.5 text-sky-300 shrink-0" />
              <span>下载原生包 (.zip)</span>
            </button>
          </div>
        </div>
      </header>

      {/* Floating Feedback Banner */}
      {toastBanner && (
        <div className="fixed bottom-5 right-5 z-50 flex items-center gap-2.5 rounded-full border border-slate-200 bg-slate-900 px-4 py-2 text-xs font-medium text-white shadow-lg">
          <span>{toastBanner}</span>
          <button
            type="button"
            onClick={() => setToastBanner(null)}
            className="text-slate-400 hover:text-white cursor-pointer"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        </div>
      )}

      <main className="mx-auto max-w-[1180px] space-y-10 px-6 py-8">
        {/* Top Workbench: 1:1 Interactive Minimalist macOS Popover Preview + One-Command DMG Packaging */}
        <section className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
          {/* Left: True-Scale 444px Minimalist macOS Popover Live Interactive Replica */}
          <div className="lg:col-span-6 flex flex-col items-center">
            {/* Simulated macOS Menu Bar Status Item Trigger (Defaults to 22pt Compact Anti-Notch Icon) */}
            <div className="mb-2.5 flex w-full max-w-[444px] items-center justify-center gap-2">
              <button
                type="button"
                onClick={() => setIsPopoverShown((prev) => !prev)}
                title="点击模拟 macOS 菜单栏常驻图标（默认 22pt 紧凑仅图标，切到 Chrome/IDE 长菜单或刘海屏绝不折叠隐藏）"
                className={`inline-flex h-7 items-center gap-1.5 rounded-md border px-2 text-xs font-medium transition-colors cursor-pointer select-none ${
                  isPopoverShown
                    ? 'border-sky-200 bg-sky-50/90 text-slate-900 shadow-xs'
                    : 'border-slate-200/90 bg-white/90 text-slate-700 hover:bg-slate-100/80'
                }`}
              >
                <span className="relative inline-flex items-center justify-center">
                  <RolePackSpriteIcon packId={selectedPackId} status="working" size={18} />
                  {menuBarMode === 'iconOnly' && (
                    <span className="absolute -bottom-0.5 -right-0.5 h-2 w-2 rounded-full border border-white bg-sky-500" />
                  )}
                </span>
                {menuBarMode === 'compactAmount' && (
                  <span className="font-mono text-[11.5px] tabular-nums">
                    {currencyMode === 'CNY'
                      ? `¥${Math.round(activeScope.totalCostCny)}`
                      : `$${Math.round(activeScope.totalCostCny / FX_USD_TO_CNY)}`}
                  </span>
                )}
                {menuBarMode === 'fullStatus' && (
                  <span className="font-mono text-[11.5px] tabular-nums">
                    工作 · {formatMoneyDisplay(activeScope.totalCostCny, currencyMode)}
                  </span>
                )}
              </button>
              <span className="text-[11px] text-slate-400">
                {menuBarMode === 'iconOnly'
                  ? '紧凑常驻图标（防切屏被长菜单挤压 · 支持 ⌘+拖拽）'
                  : isPopoverShown
                    ? '点击收起'
                    : '点击弹出'}
              </span>
            </div>

            {/* NSPopover Container with Smooth Native Pop-Out Transition */}
            <div
              className={`relative w-full max-w-[444px] origin-top rounded-[18px] border border-slate-200/90 bg-[#F8FAFC]/95 p-4 shadow-[0_24px_60px_-15px_rgba(15,23,42,0.12)] backdrop-blur-2xl space-y-3.5 transition-all duration-200 ease-out ${
                isPopoverShown
                  ? 'opacity-100 translate-y-0 scale-100'
                  : 'opacity-0 -translate-y-2 scale-95 pointer-events-none select-none'
              }`}
            >
              {/* Native macOS NSPopover Top Caret Beak */}
              <div
                aria-hidden="true"
                className="pointer-events-none absolute -top-[7px] left-1/2 h-3 w-3 -translate-x-1/2 rotate-45 rounded-tl-[2px] border-t border-l border-slate-200/90 bg-[#F8FAFC]"
              />

              {/* 1. Native Popover Header */}
              <div className="flex items-center justify-between gap-2">
                <div className="inline-flex items-center gap-2 shrink-0">
                  <AgentSpurLogo size={22} className="aspect-square shrink-0 object-contain" />
                  <span className="text-[13.5px] font-bold tracking-tight text-slate-900 whitespace-nowrap">
                    AgentSpur
                  </span>
                  <span className="inline-flex h-7 items-center gap-1.5 rounded-full border border-sky-200/90 bg-sky-50 px-2.5 text-[11px] font-semibold text-sky-700 tabular-nums whitespace-nowrap shrink-0">
                    <span className="h-1.5 w-1.5 rounded-full bg-sky-500 animate-pulse shrink-0" />
                    <span>正在工作 {liveTickSec}s</span>
                  </span>
                </div>

                <div className="inline-flex items-center gap-1.5 min-w-0">
                  <div className="relative inline-flex min-w-0">
                    <button
                      type="button"
                      onClick={() => {
                        setPopoverKeyMenuOpen((v) => !v);
                        setPopoverGearOpen(false);
                      }}
                      className={`inline-flex h-7 items-center gap-1 rounded-full border px-2.5 text-[11px] font-medium transition-colors cursor-pointer min-w-0 ${
                        selectedKeyId !== '__ALL__'
                          ? 'border-sky-300 bg-sky-50 text-sky-800'
                          : 'border-slate-200/95 bg-white text-slate-700 hover:bg-slate-50'
                      }`}
                    >
                      <span className="shrink-0">🔑</span>
                      <span className="max-w-[68px] truncate">{activeScope.shortLabel}</span>
                      <span className="text-slate-400 shrink-0">▾</span>
                    </button>

                    {popoverKeyMenuOpen && (
                      <div className="absolute right-0 top-8 z-30 w-56 rounded-xl border border-slate-200 bg-white p-1 shadow-lg text-[11px]">
                        {keyScopes.map((sc) => (
                          <button
                            key={sc.id}
                            type="button"
                            onClick={() => {
                              setSelectedKeyId(sc.id);
                              setPopoverKeyMenuOpen(false);
                            }}
                            className={`flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 cursor-pointer ${
                              sc.id === selectedKeyId
                                ? 'bg-sky-50 font-semibold text-sky-800'
                                : 'text-slate-700 hover:bg-slate-50'
                            }`}
                          >
                            <span className="truncate">{sc.label}</span>
                            <span className="font-mono tabular-nums text-slate-500">
                              {formatMoneyDisplay(sc.totalCostCny, currencyMode)}
                            </span>
                          </button>
                        ))}
                        <div className="my-1 border-t border-slate-100" />
                        <button
                          type="button"
                          onClick={() => {
                            setCurrencyMode((m) => (m === 'CNY' ? 'USD' : 'CNY'));
                            setPopoverKeyMenuOpen(false);
                          }}
                          className="flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 text-slate-700 hover:bg-slate-50 cursor-pointer"
                        >
                          <span>切换计费币种</span>
                          <span className="font-mono font-semibold text-sky-700">
                            {currencyMode === 'CNY' ? '¥ CNY → $ USD' : '$ USD → ¥ CNY'}
                          </span>
                        </button>
                        <div className="my-1 border-t border-slate-100" />
                        <button
                          type="button"
                          onClick={openApiKeyManagerSheet}
                          className="flex w-full items-center gap-1.5 rounded-lg px-2.5 py-1.5 font-medium text-sky-700 hover:bg-sky-50 cursor-pointer"
                        >
                          <Plus className="h-3.5 w-3.5 shrink-0" />
                          <span>添加 / 管理多 API-Key…</span>
                        </button>
                      </div>
                    )}
                  </div>

                  <button
                    type="button"
                    onClick={triggerRefresh}
                    title="立即同步实时汇率与账单 (⌘R)"
                    className="inline-flex h-7 items-center justify-center rounded-full border border-slate-200/95 bg-white px-2 font-mono text-[11px] font-medium text-slate-700 hover:bg-slate-50 transition-colors cursor-pointer shrink-0"
                  >
                    ⌘R
                  </button>

                  <div className="relative inline-flex">
                    <button
                      type="button"
                      onClick={() => {
                        setPopoverGearOpen((v) => !v);
                        setPopoverConsoleSubmenuOpen(false);
                        setPopoverKeyMenuOpen(false);
                      }}
                      className="inline-flex h-7 w-7 items-center justify-center rounded-full border border-slate-200/95 bg-white text-slate-600 hover:bg-slate-50 transition-colors cursor-pointer"
                    >
                      <Settings className="h-3.5 w-3.5 shrink-0" />
                    </button>

                    {popoverGearOpen && !popoverConsoleSubmenuOpen && (
                      <div className="absolute right-0 top-8 z-30 w-76 rounded-xl border border-slate-200 bg-white p-1.5 shadow-lg text-[11px]">
                        {(
                          [
                            ['iconOnly', '菜单栏：仅灵动图标（防切屏隐藏）'],
                            ['compactAmount', '菜单栏：图标 + 简短金额'],
                            ['fullStatus', '菜单栏：图标 + 状态与金额'],
                          ] as const
                        ).map(([modeKey, label]) => (
                          <button
                            key={modeKey}
                            type="button"
                            onClick={() => {
                              setMenuBarMode(modeKey);
                              setPopoverGearOpen(false);
                            }}
                            className={`flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 cursor-pointer ${
                              menuBarMode === modeKey
                                ? 'bg-sky-50 font-semibold text-sky-800'
                                : 'text-slate-700 hover:bg-slate-50'
                            }`}
                          >
                            <span>{label}</span>
                            <span className="font-mono text-sky-600">{menuBarMode === modeKey ? '✓' : ''}</span>
                          </button>
                        ))}
                        <div className="my-1 border-t border-slate-100" />
                        <button
                          type="button"
                          onClick={() => {
                            setFloatingPillEnabled((v) => !v);
                            setPopoverGearOpen(false);
                          }}
                          className={`flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 cursor-pointer ${
                            floatingPillEnabled
                              ? 'bg-sky-50 font-semibold text-sky-800'
                              : 'text-slate-700 hover:bg-slate-50'
                          }`}
                        >
                          <span>刘海遮挡/全屏时自动悬浮胶囊</span>
                          <span className="font-mono text-sky-600">{floatingPillEnabled ? '✓' : ''}</span>
                        </button>
                        <button
                          type="button"
                          onClick={() => {
                            setLaunchAtLogin((v) => !v);
                            setPopoverGearOpen(false);
                          }}
                          className={`flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 cursor-pointer ${
                            launchAtLogin
                              ? 'bg-sky-50 font-semibold text-sky-800'
                              : 'text-slate-700 hover:bg-slate-50'
                          }`}
                        >
                          <span>开机自动启动驻留菜单栏</span>
                          <span className="font-mono text-sky-600">{launchAtLogin ? '✓' : ''}</span>
                        </button>
                        <div className="my-1 border-t border-slate-100" />
                        <button
                          type="button"
                          onClick={() => {
                            setAutoFocusTerminal((v) => !v);
                            setPopoverGearOpen(false);
                          }}
                          className="flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 text-slate-700 hover:bg-slate-50 cursor-pointer"
                        >
                          <span>终端自动聚焦高亮</span>
                          <span className="font-mono text-sky-600">{autoFocusTerminal ? '✓' : ''}</span>
                        </button>
                        <button
                          type="button"
                          onClick={() => setPopoverConsoleSubmenuOpen(true)}
                          className={`flex w-full items-center justify-between gap-2 rounded-lg px-2.5 py-1.5 cursor-pointer ${
                            selectedConsoleId !== null
                              ? 'bg-sky-50 font-semibold text-sky-800'
                              : 'text-slate-700 hover:bg-slate-50'
                          }`}
                        >
                          <span className="shrink-0">选择聚焦控制台</span>
                          <span className="truncate font-mono text-[10.5px] text-sky-700">
                            {selectedConsoleId
                              ? `已固定 · ${PREVIEW_CONSOLES.find((c) => c.id === selectedConsoleId)?.shortSummary ?? ''} ▸`
                              : `自动跟随 (共 ${PREVIEW_CONSOLES.length} 个) ▸`}
                          </span>
                        </button>
                        <div className="my-1 border-t border-slate-100" />
                        <button
                          type="button"
                          onClick={openApiKeyManagerSheet}
                          className="flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 text-slate-700 hover:bg-slate-50 cursor-pointer"
                        >
                          <span>管理多 API-Key 分组…</span>
                          <KeyRound className="h-3 w-3 text-sky-600 shrink-0" />
                        </button>
                        <button
                          type="button"
                          onClick={handleTestNotification}
                          className="flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 text-slate-700 hover:bg-slate-50 cursor-pointer"
                        >
                          <span>发送测试通知与提示音</span>
                          <span>🔔</span>
                        </button>
                      </div>
                    )}

                    {popoverGearOpen && popoverConsoleSubmenuOpen && (
                      <div className="absolute right-0 top-8 z-30 w-84 rounded-xl border border-slate-200 bg-white p-1.5 shadow-xl text-[11px]">
                        <button
                          type="button"
                          onClick={() => setPopoverConsoleSubmenuOpen(false)}
                          className="flex w-full items-center justify-between rounded-lg bg-slate-50 px-2.5 py-1.5 font-semibold text-sky-700 hover:bg-sky-50 cursor-pointer"
                        >
                          <span>‹ 返回设置菜单</span>
                          <span className="font-mono text-[10px] font-medium text-slate-500">
                            共 {PREVIEW_CONSOLES.length} 个控制台
                          </span>
                        </button>
                        <div className="my-1 border-t border-slate-100" />
                        <div className="max-h-[212px] overflow-y-auto space-y-0.5 pr-0.5">
                          <button
                            type="button"
                            onClick={() => {
                              setSelectedConsoleId(null);
                              setPopoverConsoleSubmenuOpen(false);
                              setPopoverGearOpen(false);
                              triggerToast('已切换为：跟随前台活跃终端 (自动识别)');
                            }}
                            className={`flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 cursor-pointer ${
                              selectedConsoleId === null
                                ? 'bg-sky-50 font-semibold text-sky-800'
                                : 'text-slate-700 hover:bg-slate-50'
                            }`}
                          >
                            <span>跟随前台活跃终端 (自动识别)</span>
                            <span className="font-mono text-sky-600">{selectedConsoleId === null ? '✓' : ''}</span>
                          </button>
                          <div className="my-1 border-t border-slate-100" />
                          {PREVIEW_CONSOLES.map((win) => {
                            const isSel = selectedConsoleId === win.id;
                            return (
                              <button
                                key={win.id}
                                type="button"
                                onClick={() => {
                                  setSelectedConsoleId(win.id);
                                  setPopoverConsoleSubmenuOpen(false);
                                  setPopoverGearOpen(false);
                                  triggerToast(`已固定聚焦：${win.shortSummary}`);
                                }}
                                className={`flex w-full items-center justify-between gap-2 rounded-lg px-2.5 py-1.5 cursor-pointer ${
                                  isSel
                                    ? 'bg-sky-50 font-semibold text-sky-800'
                                    : 'text-slate-700 hover:bg-slate-50'
                                }`}
                              >
                                <span className="truncate text-left">{win.indexLabel}</span>
                                <span className="shrink-0 font-mono text-[10.5px] font-semibold text-sky-600">
                                  {isSel ? '✓' : win.active ? '前台' : ''}
                                </span>
                              </button>
                            );
                          })}
                          <div className="my-1 border-t border-slate-100" />
                          <button
                            type="button"
                            onClick={() => triggerToast(`已重新扫描本机全部 ${PREVIEW_CONSOLES.length} 个控制台窗口`)}
                            className="flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 font-semibold text-sky-700 hover:bg-sky-50 cursor-pointer"
                          >
                            <span>↻ 重新扫描本机所有控制台</span>
                          </button>
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              </div>

              {/* 2. Minimalist Cost & Dual-Tone Cache Overview Card (Hover for Full Breakdown) */}
              <div
                onMouseEnter={() => setShowCostTooltip(true)}
                onMouseLeave={() => setShowCostTooltip(false)}
                className="relative rounded-xl border border-slate-200/90 bg-white px-4 py-3.5 space-y-2.5 transition-colors hover:border-slate-300/90"
              >
                <div className="flex items-center justify-between text-[11px] text-slate-500">
                  <span className="font-medium">
                    {selectedKeyId === '__ALL__' ? '今日 10/28 总开销' : `今日 · ${activeScope.shortLabel}`}
                  </span>
                  <button
                    type="button"
                    onClick={openApiKeyManagerSheet}
                    className="font-mono text-[10.5px] text-slate-400 hover:text-sky-600 transition-colors cursor-pointer"
                  >
                    余额 ¥2785.36 · 闲时 5 折
                  </button>
                </div>

                <div className="flex items-baseline justify-between gap-2">
                  <div className="flex items-baseline gap-2">
                    <span className="font-mono text-[26px] leading-none font-bold tracking-tight text-slate-900 tabular-nums">
                      {formatMoneyDisplay(activeScope.totalCostCny, currencyMode)}
                    </span>
                    <span className="font-mono text-xs font-medium text-slate-400 tabular-nums">
                      ≈ {formatMoneyDisplay(activeScope.totalCostCny, currencyMode === 'CNY' ? 'USD' : 'CNY')}
                    </span>
                  </div>
                  <span className="font-mono text-[11px] font-semibold text-emerald-600 tabular-nums">
                    已省 {formatMoneyDisplay(activeScope.cacheSavedCny + activeScope.offPeakSavedCny, currencyMode)}
                  </span>
                </div>

                {/* Single Dual-Tone Cache Hit Progress Bar */}
                <div className="space-y-1.5 pt-0.5">
                  <div className="flex items-center justify-between text-[11px] font-mono tabular-nums">
                    <span className="font-semibold text-sky-700">
                      Cache 命中率 {activeScope.cacheHitPct.toFixed(1)}%
                    </span>
                    <span className="text-[10.5px] text-slate-400">
                      {activeScope.requestCount.toLocaleString()} 次 · 悬停看明细
                    </span>
                  </div>
                  <div className="h-[7px] w-full overflow-hidden rounded-full bg-slate-200/85">
                    <div
                      className="h-full rounded-full bg-gradient-to-r from-sky-600 to-sky-400 transition-all duration-300"
                      style={{ width: `${activeScope.cacheHitPct}%` }}
                    />
                  </div>
                </div>

                {/* Hover Tooltip Breakdown (1:1 Flush-Centered Match with Native CostBreakdownHoverCardView) */}
                {showCostTooltip && (
                  <div className="pointer-events-none absolute inset-x-0 top-full mt-1.5 z-30 rounded-xl border border-slate-700/80 bg-[#0F172A]/[0.97] px-4 py-3 text-[10.8px] leading-relaxed text-slate-100 shadow-2xl space-y-1">
                    <div className="flex items-center justify-between border-b border-white/10 pb-1.5 mb-1">
                      <span className="font-sans text-[11.4px] font-semibold text-sky-300">
                        今日 10/28 精算透视明细
                      </span>
                      <span className="font-mono text-[10.2px] text-slate-400 tabular-nums">
                        V4.1-Flash · $1 = ¥{FX_USD_TO_CNY}
                      </span>
                    </div>
                    <div className="flex items-center justify-between gap-2 font-mono tabular-nums">
                      <span className="font-sans text-slate-400">缓存命中 (Hit)</span>
                      <span className="text-emerald-400">
                        {activeScope.hitTokensLabel} ({activeScope.cacheHitPct}%) · 已省 ¥{activeScope.cacheSavedCny.toFixed(2)}
                      </span>
                    </div>
                    <div className="flex items-center justify-between gap-2 font-mono tabular-nums">
                      <span className="font-sans text-slate-400">未命中输入 (Miss)</span>
                      <span>{activeScope.missTokensLabel}</span>
                    </div>
                    <div className="flex items-center justify-between gap-2 font-mono tabular-nums">
                      <span className="font-sans text-slate-400">输出 + 思维链</span>
                      <span>{activeScope.outputTokensLabel}</span>
                    </div>
                    <div className="flex items-center justify-between gap-2 font-mono tabular-nums">
                      <span className="font-sans text-slate-400">忙闲时段拆分</span>
                      <span>忙时 ¥{activeScope.peakCostCny.toFixed(2)} · 闲时5折 ¥{activeScope.offPeakCostCny.toFixed(2)}</span>
                    </div>
                    <div className="flex items-center justify-between gap-2 font-mono tabular-nums">
                      <span className="font-sans text-slate-400">OpenCode 静态估</span>
                      <span className="text-slate-400">${activeScope.opencodeStaticUsd.toFixed(4)} (未计忙闲时差异)</span>
                    </div>
                    <div className="flex items-center justify-between gap-2 font-mono tabular-nums">
                      <span className="font-sans text-slate-400">官方实时余额</span>
                      <span className="text-sky-300">¥2785.36 · api.deepseek.com · sk-***01</span>
                    </div>
                  </div>
                )}
              </div>

              {/* 3. Segmented Filter + Minimalist Accordion Session List (Default Collapsed, No Heavy Blue Boxes) */}
              <div className="grid grid-cols-4 gap-1 rounded-lg bg-slate-200/65 p-0.5 text-[11px] font-medium">
                {(
                  [
                    ['all', `全部 ${scopedSessions.length}`],
                    ['pending', `待处理 ${pendingCount}`],
                    ['running', `运行中 ${runningCount}`],
                    ['completed', `已完成 ${completedCount}`],
                  ] as [SessionFilter, string][]
                ).map(([key, label]) => (
                  <button
                    key={key}
                    type="button"
                    onClick={() => setSessionFilter(key)}
                    className={`h-6 rounded-md transition-all cursor-pointer tabular-nums ${
                      sessionFilter === key
                        ? 'bg-white font-semibold text-slate-900 shadow-xs'
                        : 'text-slate-600 hover:text-slate-900'
                    }`}
                  >
                    {label}
                  </button>
                ))}
              </div>

              <div className="rounded-xl border border-slate-200/90 bg-white p-1.5 space-y-0.5 min-h-[168px] max-h-[208px] overflow-y-auto">
                {filteredSessions.length === 0 ? (
                  <div className="flex h-[152px] items-center justify-center text-xs text-slate-400">
                    当前筛选分组暂无会话
                  </div>
                ) : (
                  filteredSessions.map((sess) => {
                    const isExpanded = expandedSessionIds.has(sess.id);
                    const isActive = sess.status === 'working' || sess.status === 'thinking' || sess.status === 'confirm';
                    const dimmed = sessionFilter === 'all' && sess.status === 'completed';
                    const isFocusedRow = autoFocusTerminal && sess.focused;

                    return (
                      <div key={sess.id} className={dimmed ? 'opacity-50 hover:opacity-90 transition-opacity' : ''}>
                        <div
                          onClick={() => triggerToast(`↗ 已跳转至真实控制台：${sess.terminalLabel}`)}
                          title={`点击直达终端: ${sess.terminalLabel}\n目录: ${sess.directory}\n主会话: ¥${sess.ownCostCny.toFixed(4)} · Cache ${sess.cachePct}% · ${sess.requests}次请求`}
                          className={`group flex h-[34px] items-center gap-2 rounded-lg px-2.5 text-xs transition-colors cursor-pointer ${
                            isFocusedRow
                              ? 'border border-sky-200/80 bg-sky-50/55 hover:bg-sky-50'
                              : 'border border-transparent hover:bg-slate-50'
                          }`}
                        >
                          <RolePackSpriteIcon packId={selectedPackId} status={sess.status} size={18} />
                          <span
                            className={`min-w-0 flex-1 truncate ${
                              isActive ? 'font-semibold text-slate-900' : 'font-normal text-slate-800'
                            }`}
                          >
                            {sess.title}
                          </span>

                          {sess.subAgents.length > 0 && (
                            <button
                              type="button"
                              onClick={(e) => toggleExpandSession(sess.id, e)}
                              className="inline-flex h-5 items-center gap-0.5 rounded px-1.5 font-mono text-[10.5px] font-semibold text-slate-500 hover:bg-slate-200/65 hover:text-slate-800 shrink-0 cursor-pointer"
                            >
                              {isExpanded ? (
                                <ChevronDown className="h-3 w-3" />
                              ) : (
                                <ChevronRight className="h-3 w-3" />
                              )}
                              <span>{sess.subAgents.length}</span>
                            </button>
                          )}

                          <span className="font-mono text-[11px] font-medium text-slate-500 tabular-nums shrink-0">
                            {formatMoneyDisplay(sess.costCny, currencyMode)}
                          </span>

                          <span
                            className={`font-mono text-[11px] font-semibold tabular-nums shrink-0 w-10 text-right ${
                              isActive ? 'text-sky-600' : 'text-slate-400'
                            }`}
                          >
                            {isActive ? `${sess.elapsedSec + (liveTickSec - 33)}s` : '完成'}
                          </span>

                          <ArrowUpRight className="h-3.5 w-3.5 text-slate-300 group-hover:text-sky-600 shrink-0 transition-colors" />
                        </div>

                        {isExpanded &&
                          sess.subAgents.map((sub) => (
                            <div
                              key={sub.id}
                              onClick={() => triggerToast(`↗ 已跳转至子任务终端：${sess.terminalLabel}`)}
                              className="flex h-[26px] items-center justify-between gap-2 rounded-md pl-7 pr-2.5 text-[11px] text-slate-600 hover:bg-slate-50 cursor-pointer"
                            >
                              <div className="flex items-center gap-1.5 min-w-0">
                                <span className="font-mono text-slate-300 shrink-0">└─</span>
                                <span className="font-mono font-semibold text-sky-700 shrink-0">
                                  {sub.role}
                                </span>
                                <span className="truncate text-slate-600">{sub.title}</span>
                              </div>
                              <span className="font-mono text-[10.5px] text-slate-400 tabular-nums shrink-0">
                                {formatMoneyDisplay(sub.costCny, currencyMode)} · {sub.cachePct}%
                              </span>
                            </div>
                          ))}
                      </div>
                    );
                  })
                )}
              </div>

              {/* 4. Compact 24H Sparkline Bar Chart (Zero Axes, Subtle Peak Tint, Hover Readout) */}
              <div className="space-y-1.5">
                <div className="flex items-center justify-between text-[11px]">
                  <span className="font-semibold text-slate-600">24H 趋势</span>
                  <span
                    className={`font-mono text-[10.5px] tabular-nums ${
                      hoveredBarHour !== null ? 'font-semibold text-sky-700' : 'text-slate-400'
                    }`}
                  >
                    {hoveredBarHour !== null
                      ? `${String(hoveredBarHour).padStart(2, '0')}:00-${String((hoveredBarHour + 1) % 24).padStart(2, '0')}:00: ${activeScope.hourlyReqs[hoveredBarHour]}次 | ${formatMoneyDisplay(activeScope.hourlyCostsCny[hoveredBarHour], currencyMode)}`
                      : '00:00 - 24:00 · 悬停看明细'}
                  </span>
                </div>

                <div
                  onMouseLeave={() => setHoveredBarHour(null)}
                  className="grid h-[54px] grid-cols-24 items-end gap-[3px] rounded-xl border border-slate-200/90 bg-white px-2.5 py-2"
                >
                  {activeScope.hourlyReqs.map((req, hr) => {
                    const isPeak = (hr >= 9 && hr < 12) || (hr >= 14 && hr < 18);
                    const isHovered = hoveredBarHour === hr;
                    const ratio = req > 0 ? Math.max(0.14, req / maxHourlyReq) : 0.06;
                    return (
                      <div
                        key={hr}
                        onMouseEnter={() => setHoveredBarHour(hr)}
                        className={`flex h-full items-end justify-center rounded-xs cursor-pointer ${
                          isPeak ? 'bg-amber-500/[0.055]' : ''
                        }`}
                      >
                        <div
                          className={`w-full rounded-[2px] transition-all ${
                            isHovered
                              ? 'bg-sky-700'
                              : req === 0
                                ? 'bg-slate-200'
                                : hr === 15
                                  ? 'bg-sky-600'
                                  : 'bg-sky-400/85'
                          }`}
                          style={{ height: `${Math.round(ratio * 100)}%` }}
                        />
                      </div>
                    );
                  })}
                </div>
              </div>

              {/* 5. Clean Single-Row Footer Toolbar */}
              <div className="flex items-center justify-between pt-0.5">
                <div className="relative inline-flex">
                  <button
                    type="button"
                    onClick={() => setPackMenuOpen((v) => !v)}
                    className="inline-flex h-7 items-center gap-1 rounded-full border border-slate-200/95 bg-white px-2.5 text-[11px] font-medium text-slate-700 hover:bg-slate-50 transition-colors cursor-pointer"
                  >
                    <span>{activePack.label}</span>
                    <span className="text-slate-400">▾</span>
                  </button>

                  {packMenuOpen && (
                    <div className="absolute bottom-8 left-0 z-30 w-44 rounded-xl border border-slate-200 bg-white p-1 shadow-lg text-[11px]">
                      {ROLE_PACK_OPTIONS.map((p) => (
                        <button
                          key={p.id}
                          type="button"
                          onClick={() => {
                            setSelectedPackId(p.id);
                            setPackMenuOpen(false);
                          }}
                          className={`flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 cursor-pointer ${
                            p.id === selectedPackId
                              ? 'bg-sky-50 font-semibold text-sky-800'
                              : 'text-slate-700 hover:bg-slate-50'
                          }`}
                        >
                          <span>{p.label}</span>
                          {p.id === selectedPackId && <span>✓</span>}
                        </button>
                      ))}
                    </div>
                  )}
                </div>

                <div className="inline-flex items-center gap-1.5">
                  <button
                    type="button"
                    onClick={handleToggleMute}
                    className={`inline-flex h-7 items-center gap-1 rounded-full border px-2.5 text-[11px] font-medium transition-colors cursor-pointer ${
                      notificationsMuted
                        ? 'border-slate-200 bg-white text-slate-500 hover:bg-slate-50'
                        : 'border-sky-200 bg-sky-50 text-sky-800 hover:bg-sky-100/70'
                    }`}
                  >
                    {notificationsMuted ? (
                      <>
                        <BellOff className="h-3 w-3 shrink-0" />
                        <span>已静音</span>
                      </>
                    ) : (
                      <>
                        <Bell className="h-3 w-3 shrink-0" />
                        <span>提醒开启</span>
                      </>
                    )}
                  </button>

                  <button
                    type="button"
                    onClick={() => {
                      setIsPopoverShown(false);
                      triggerToast('已收起模拟 NSPopover（点击上方菜单栏胶囊可再次平滑弹出）');
                    }}
                    className="inline-flex h-7 items-center gap-1 rounded-full border border-slate-200/95 bg-white px-2.5 text-[11px] font-medium text-slate-600 hover:bg-slate-50 hover:text-slate-900 transition-colors cursor-pointer"
                  >
                    <span>✕ 退出</span>
                  </button>
                </div>
              </div>

              {/* KeyableSheetPanel Simulation (Topmost Focusable NSPanel Above NSPopover) */}
              {apiKeySheetOpen && (
                <div
                  onClick={() => setApiKeySheetOpen(false)}
                  className="absolute inset-0 z-40 flex items-center justify-center rounded-[18px] bg-slate-900/30 p-4 backdrop-blur-[2px] transition-opacity duration-150"
                >
                  <form
                    onClick={(e) => e.stopPropagation()}
                    onSubmit={handleSaveApiKeyProfile}
                    className="w-full rounded-2xl border border-slate-200 bg-white p-4 shadow-2xl space-y-3"
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-[13.5px] font-bold text-slate-900">
                        API-Key 自动读取与多分组管理
                      </span>
                      <div className="inline-flex items-center gap-1.5">
                        <button
                          type="button"
                          onClick={() => triggerToast('已重新只读扫描 opencode.db / auth.json / opencode.json')}
                          className="inline-flex h-7 items-center gap-1 rounded-lg border border-slate-200 bg-slate-50 px-2 text-[11px] font-medium text-slate-700 hover:bg-slate-100 cursor-pointer"
                        >
                          <RefreshCw className="h-3 w-3 text-sky-600" />
                          <span>重新读取DB</span>
                        </button>
                        <button
                          type="button"
                          onClick={() => setApiKeySheetOpen(false)}
                          className="inline-flex h-7 w-7 items-center justify-center rounded-full border border-slate-200 bg-white text-slate-500 hover:bg-slate-50 hover:text-slate-900 cursor-pointer"
                        >
                          <X className="h-3.5 w-3.5" />
                        </button>
                      </div>
                    </div>

                    <p className="text-[11px] leading-relaxed text-slate-500">
                      已自动只读提取 <code className="font-mono text-slate-700">opencode.db</code> /{' '}
                      <code className="font-mono text-slate-700">auth.json</code> /{' '}
                      <code className="font-mono text-slate-700">opencode.json</code> 中的 Key；也可直接输入或点右侧「粘贴」手动补充。
                    </p>

                    <div className="space-y-1.5">
                      <div className="text-[11px] font-semibold text-slate-600">
                        当前可用 Key 与自动识别通道
                      </div>
                      <div className="max-h-28 space-y-1 overflow-y-auto rounded-xl border border-slate-200/85 bg-slate-50/80 p-1.5">
                        {keyScopes
                          .filter((sc) => sc.id !== '__ALL__')
                          .map((sc) => {
                            const active = sc.id === selectedKeyId;
                            const nonAllCount = keyScopes.filter((k) => k.id !== '__ALL__').length;
                            return (
                              <div
                                key={sc.id}
                                className={`flex items-center justify-between gap-2 rounded-lg border px-2.5 py-1.5 text-[11px] ${
                                  active
                                    ? 'border-sky-200 bg-sky-50 text-sky-900'
                                    : 'border-slate-200/70 bg-white text-slate-700'
                                }`}
                              >
                                <div className="min-w-0 truncate">
                                  <span className="font-medium">{sc.label}</span>
                                  <span className="mx-1.5 text-slate-300" aria-hidden="true">
                                    ·
                                  </span>
                                  <span className="text-[10.5px] text-slate-500">
                                    {sc.autoSource ? `自动 · ${sc.autoSource}` : '手动添加'}
                                  </span>
                                </div>
                                <div className="inline-flex items-center gap-1.5 shrink-0">
                                  <button
                                    type="button"
                                    onClick={() => {
                                      setFormKeyName(sc.shortLabel.split(' (')[0]);
                                      keyNameInputRef.current?.focus();
                                    }}
                                    className="rounded px-1.5 py-0.5 text-[10.5px] font-medium text-slate-500 hover:bg-slate-100 hover:text-slate-900 cursor-pointer"
                                  >
                                    编辑
                                  </button>
                                  <button
                                    type="button"
                                    onClick={() => {
                                      setSelectedKeyId(sc.id);
                                      setApiKeySheetOpen(false);
                                    }}
                                    disabled={active}
                                    className={`rounded px-1.5 py-0.5 text-[10.5px] font-semibold cursor-pointer ${
                                      active
                                        ? 'text-sky-600 cursor-default'
                                        : 'text-sky-700 hover:bg-sky-50'
                                    }`}
                                  >
                                    {active ? '当前' : '启用'}
                                  </button>
                                  {!sc.autoSource && nonAllCount > 1 && (
                                    <button
                                      type="button"
                                      onClick={() => handleDeleteApiKeyProfile(sc.id)}
                                      className="inline-flex items-center rounded p-0.5 text-rose-500 hover:bg-rose-50 cursor-pointer"
                                      title="删除分组"
                                    >
                                      <Trash2 className="h-3 w-3" />
                                    </button>
                                  )}
                                </div>
                              </div>
                            );
                          })}
                      </div>
                    </div>

                    <div className="space-y-2">
                      <div className="text-[11px] font-semibold text-slate-600">
                        手动补充或覆盖分组（同名自动覆盖）
                      </div>
                      <input
                        ref={keyNameInputRef}
                        type="text"
                        value={formKeyName}
                        onChange={(e) => setFormKeyName(e.target.value)}
                        placeholder="分组名称（如：DeepSeek 官方、个人备用Key）"
                        className="h-8 w-full rounded-lg border border-slate-200 px-2.5 text-xs text-slate-900 placeholder:text-slate-400 focus:border-sky-400 focus:outline-none"
                      />
                      <div className="flex items-center gap-1.5">
                        <input
                          type="text"
                          value={formKeySecret}
                          onChange={(e) => setFormKeySecret(e.target.value)}
                          placeholder="sk-...（支持 ⌘V 或右侧一键粘贴，实时查余额）"
                          className="h-8 min-w-0 flex-1 rounded-lg border border-slate-200 px-2.5 font-mono text-xs text-slate-900 placeholder:font-sans placeholder:text-slate-400 focus:border-sky-400 focus:outline-none"
                        />
                        <button
                          type="button"
                          onClick={async () => {
                            try {
                              const text = await navigator.clipboard.readText();
                              if (text.trim()) {
                                setFormKeySecret(text.trim());
                                if (!formKeyName.trim()) {
                                  setFormKeyName(`备用Key-${keyScopes.length}`);
                                }
                                triggerToast(`已粘贴 (${maskApiKey(text.trim())})`);
                              }
                            } catch {
                              triggerToast('请直接在输入框按 ⌘V 粘贴');
                            }
                          }}
                          className="inline-flex h-8 shrink-0 items-center rounded-lg border border-slate-200 bg-slate-50 px-2.5 text-xs font-medium text-slate-700 hover:bg-slate-100 cursor-pointer"
                        >
                          粘贴
                        </button>
                      </div>
                      <input
                        type="text"
                        value={formKeyDir}
                        onChange={(e) => setFormKeyDir(e.target.value)}
                        placeholder="工作目录匹配词（可选，如 client-b 自动分账）"
                        className="h-8 w-full rounded-lg border border-slate-200 px-2.5 text-xs text-slate-900 placeholder:text-slate-400 focus:border-sky-400 focus:outline-none"
                      />
                    </div>

                    <div className="flex items-center justify-end gap-2 pt-1">
                      <button
                        type="button"
                        onClick={() => setApiKeySheetOpen(false)}
                        className="inline-flex h-7 items-center rounded-full border border-slate-200 bg-white px-3 text-xs font-medium text-slate-700 hover:bg-slate-50 cursor-pointer"
                      >
                        取消
                      </button>
                      <button
                        type="submit"
                        className="inline-flex h-7 items-center rounded-full border border-sky-300 bg-sky-50 px-3.5 text-xs font-semibold text-sky-800 hover:bg-sky-100/80 cursor-pointer"
                      >
                        保存并启用
                      </button>
                    </div>
                  </form>
                </div>
              )}
            </div>
          </div>

          {/* Right: Packaging Guide & Refactoring Architecture Summary */}
          <div className="lg:col-span-6 space-y-6">
            <div className="rounded-2xl border border-slate-200/85 bg-white p-7 space-y-6">
              <div className="space-y-2">
                <div className="text-xs font-mono text-slate-500">
                  macOS 14.0+ · 原生 AppKit + SQLite3 · 零 WebView 依赖
                </div>
                <h1 className="text-2xl font-semibold tracking-tight text-slate-900">
                  极简重构版 AgentSpur.dmg 一键构建
                </h1>
                <p className="text-sm leading-relaxed text-slate-600">
                  左侧为本次升级后的 1:1 交互预览（已支持自动只读提取本地 OpenCode 的 API-Key 与通道，并修复手动输入焦点）。下载下方原生源码包后，在 Mac 上双击{' '}
                  <code className="font-mono text-xs text-slate-800">双击打包DMG.command</code> 或运行构建脚本，即可生成最新{' '}
                  <code className="font-mono text-xs text-slate-800">AgentSpur.dmg</code>。
                </p>
              </div>

              <div className="flex flex-wrap items-center gap-3">
                <button
                  type="button"
                  onClick={handleDownloadNativeZip}
                  className="inline-flex h-10 items-center gap-2 rounded-full bg-slate-900 px-5 text-xs font-semibold text-white hover:bg-slate-800 transition-colors cursor-pointer"
                >
                  <Download className="h-4 w-4 text-sky-300 shrink-0" />
                  <span>下载 AgentSpur-macOS-Native.zip</span>
                </button>

                <button
                  type="button"
                  onClick={handleTestNotification}
                  className="inline-flex h-10 items-center gap-2 rounded-full border border-slate-200 bg-white px-4 text-xs font-medium text-slate-700 hover:bg-slate-50 transition-colors cursor-pointer"
                >
                  <Volume2 className="h-4 w-4 text-sky-600 shrink-0" />
                  <span>试听任务完成提示音</span>
                </button>
              </div>

              <div className="flex items-center justify-between gap-3 rounded-xl border border-slate-200/85 bg-slate-50 px-4 py-3 font-mono text-xs text-slate-800">
                <div className="flex items-center gap-2.5 min-w-0 truncate">
                  <Terminal className="h-4 w-4 text-sky-600 shrink-0" />
                  <span className="truncate">cd AgentSpur && chmod +x build_dmg.sh && ./build_dmg.sh</span>
                </div>
                <button
                  type="button"
                  onClick={handleCopyCommand}
                  className="inline-flex h-7 items-center gap-1 rounded-full border border-slate-200 bg-white px-3 text-[11px] font-sans font-medium text-slate-600 hover:text-slate-900 hover:border-slate-300 transition-colors shrink-0 cursor-pointer"
                >
                  {copiedCmd ? (
                    <>
                      <Check className="h-3.5 w-3.5 text-sky-600" />
                      <span>已复制</span>
                    </>
                  ) : (
                    <>
                      <Copy className="h-3.5 w-3.5" />
                      <span>复制命令</span>
                    </>
                  )}
                </button>
              </div>

              {/* Structured Summary Grid of Key Fixes */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-2 border-t border-slate-100 text-xs">
                <div className="space-y-1">
                  <div className="font-semibold text-slate-900">1. 自动只读提取本地 API-Key 与余额</div>
                  <p className="text-slate-500 leading-relaxed">
                    自动扫描 <code className="font-mono">opencode.db</code> 凭据表、同目录 <code className="font-mono">auth.json</code>、<code className="font-mono">opencode.json</code> 与项目 <code className="font-mono">.env</code>，免手动填 Key 即可分账与查余额。
                  </p>
                </div>
                <div className="space-y-1">
                  <div className="font-semibold text-slate-900">2. 修复 Key 弹窗键盘焦点与置顶层级</div>
                  <p className="text-slate-500 leading-relaxed">
                    采用独立 <code className="font-mono">KeyableSheetPanel</code> (<code className="font-mono">canBecomeKey=true</code> · <code className="font-mono">popUpMenu+5</code>)，彻底解决 <code className="font-mono">.accessory</code> 模式下无法打字粘贴的问题。
                  </p>
                </div>
                <div className="space-y-1">
                  <div className="font-semibold text-slate-900">3. 饱满等比小鲸图标 + 极简账单透视</div>
                  <p className="text-slate-500 leading-relaxed">
                    重写 <code className="font-mono">RetinaAspectFitImageView</code> 与 1:1 饱满小鲸路径，彻底消除拉伸压缩；子任务默认折叠，已完成任务半透明降噪。
                  </p>
                </div>
                <div className="space-y-1">
                  <div className="font-semibold text-slate-900">4. &lt;1ms 多 Key 预聚合 + 原生提示音</div>
                  <p className="text-slate-500 leading-relaxed">
                    本地缓存库建立 <code className="font-mono">idx_usage_key_time</code> 索引并内存预聚合多 Key 趋势，秒切零卡顿；补齐前台横幅与 <code className="font-mono">NSSound</code> 音效。
                  </p>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* Native Swift & DMG Packaging Source Code Browser */}
        <section className="rounded-2xl border border-slate-200/85 bg-white overflow-hidden">
          <div className="flex flex-wrap items-center justify-between gap-4 border-b border-slate-200/75 px-6 py-3.5">
            <div className="flex items-center gap-2 text-xs font-semibold text-slate-800">
              <FileCode2 className="h-4 w-4 text-sky-600 shrink-0" />
              <span>macOS 原生工程源码检视 ({NATIVE_FILES.length} 个文件)</span>
            </div>

            <button
              type="button"
              onClick={handleCopyCurrentFile}
              className="inline-flex h-7 items-center gap-1.5 rounded-full border border-slate-200 bg-white px-3 text-xs font-medium text-slate-600 hover:bg-slate-50 hover:text-slate-900 transition-colors cursor-pointer whitespace-nowrap shrink-0"
            >
              {copiedFile ? (
                <>
                  <Check className="h-3.5 w-3.5 text-sky-600" />
                  <span>已复制 {selectedFile.relPath}</span>
                </>
              ) : (
                <>
                  <Copy className="h-3.5 w-3.5" />
                  <span>复制当前文件</span>
                </>
              )}
            </button>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-12 min-h-[440px]">
            <aside className="lg:col-span-4 border-b lg:border-b-0 lg:border-r border-slate-200/75 p-3 space-y-1 bg-slate-50/60">
              {NATIVE_FILES.map((item) => {
                const active = item.relPath === selectedFile.relPath;
                return (
                  <button
                    key={item.relPath}
                    type="button"
                    onClick={() => setSelectedPath(item.relPath)}
                    className={`w-full text-left rounded-lg px-3 py-2 text-xs font-mono transition-colors cursor-pointer truncate ${
                      active
                        ? 'bg-sky-50 text-sky-900 font-semibold border border-sky-200/80'
                        : 'border border-transparent text-slate-600 hover:bg-white hover:text-slate-900'
                    }`}
                  >
                    {item.label}
                  </button>
                );
              })}
            </aside>

            <div className="lg:col-span-8 p-5 overflow-auto max-h-[520px] bg-white">
              <pre className="text-xs font-mono leading-relaxed text-slate-800 whitespace-pre">
                <code>{selectedFile.content}</code>
              </pre>
            </div>
          </div>
        </section>
      </main>
    </div>
  );
}
