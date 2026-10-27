import React from 'react';
import { RefreshCw } from 'lucide-react';
import { AgentStatus, CharacterPack, QuotaState } from '../types/agent';
import { STATUS_META } from '../data/initialData';
import { AgentSpriteCanvas } from './AgentSpriteCanvas';

export type DesktopTabMode = 'workspace' | 'character_lab' | 'swift_source';

interface MacMenuBarProps {
  activeStatus: AgentStatus;
  activePack: CharacterPack;
  quota: QuotaState;
  isPopoverOpen: boolean;
  onTogglePopover: () => void;
  isRefreshingQuota: boolean;
  activeDesktopTab: DesktopTabMode;
  onSelectDesktopTab: (tab: DesktopTabMode) => void;
  focusedAppLabel: string;
}

export const MacMenuBar: React.FC<MacMenuBarProps> = ({
  activeStatus,
  activePack,
  quota,
  isPopoverOpen,
  onTogglePopover,
  isRefreshingQuota,
  activeDesktopTab,
  onSelectDesktopTab,
  focusedAppLabel,
}) => {
  const statusInfo = STATUS_META[activeStatus];

  return (
    <header className="sticky top-0 z-40 flex h-9 w-full items-center justify-between gap-8 border-b border-slate-200/80 bg-white/80 px-5 backdrop-blur-xl select-none shadow-[0_1px_2px_rgba(15,23,42,0.04)]">
      {/* Zone 1: Single-element Brand / Active macOS App Wordmark */}
      <a
        href="#top"
        onClick={(e) => {
          e.preventDefault();
          onSelectDesktopTab('workspace');
        }}
        className="text-sm font-semibold tracking-tight text-slate-900 whitespace-nowrap shrink-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-600 rounded"
      >
         {focusedAppLabel}
      </a>

      {/* Zone 2: Clean single-line text navigation links */}
      <nav className="hidden md:flex items-center gap-6 text-xs font-medium text-slate-600">
        <button
          type="button"
          onClick={() => onSelectDesktopTab('workspace')}
          className={`transition-colors duration-150 whitespace-nowrap shrink-0 hover:text-slate-900 underline-offset-4 ${
            activeDesktopTab === 'workspace'
              ? 'text-slate-900 font-semibold underline'
              : 'text-slate-600'
          }`}
        >
          opencode 桌面联动
        </button>
        <button
          type="button"
          onClick={() => onSelectDesktopTab('character_lab')}
          className={`transition-colors duration-150 whitespace-nowrap shrink-0 hover:text-slate-900 underline-offset-4 ${
            activeDesktopTab === 'character_lab'
              ? 'text-slate-900 font-semibold underline'
              : 'text-slate-600'
          }`}
        >
          15帧动画与角色包
        </button>
        <button
          type="button"
          onClick={() => onSelectDesktopTab('swift_source')}
          className={`transition-colors duration-150 whitespace-nowrap shrink-0 hover:text-slate-900 underline-offset-4 ${
            activeDesktopTab === 'swift_source'
              ? 'text-slate-900 font-semibold underline'
              : 'text-slate-600'
          }`}
        >
          原生AppKit源码
        </button>
      </nav>

      {/* Zone 3: Primary Action — Authentic macOS Light NSStatusItem (15 FPS Icon + State + Quota & Reset) */}
      <div className="flex items-center shrink-0">
        <button
          type="button"
          onClick={onTogglePopover}
          aria-expanded={isPopoverOpen}
          title="点击展开或收起 macOS 状态栏面板（仅展示看 · 按 ⌘R 刷新额度）"
          className={`flex items-center gap-2 rounded-md px-2.5 py-1 text-xs font-medium transition-colors duration-150 whitespace-nowrap shrink-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-600 ${
            isPopoverOpen
              ? 'bg-slate-900/[0.09] text-slate-950'
              : 'bg-slate-900/[0.04] text-slate-800 hover:bg-slate-900/[0.08]'
          }`}
        >
          <AgentSpriteCanvas status={activeStatus} pack={activePack} size={18} />
          <span className={`font-semibold ${statusInfo.textClass}`}>
            {statusInfo.label}
          </span>
          <span className="text-slate-400" aria-hidden="true">
            ·
          </span>
          <span className="font-mono tabular-nums text-slate-900 font-medium">
            ${quota.remainingUsd.toFixed(2)}
          </span>
          <span className="text-slate-400" aria-hidden="true">
            ·
          </span>
          <span className="font-mono tabular-nums text-slate-600">
            {quota.resetTimeLabel}
          </span>
          {isRefreshingQuota && (
            <RefreshCw className="w-3 h-3 text-sky-600 animate-spin shrink-0" />
          )}
        </button>
      </div>
    </header>
  );
};
