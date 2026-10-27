import React, { useState } from 'react';
import { RefreshCw } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import {
  AgentStatus,
  CharacterPack,
  QuotaState,
  SubAgentTask,
} from '../types/agent';
import { STATUS_META } from '../data/initialData';
import { AgentSpriteCanvas } from './AgentSpriteCanvas';

export type DesktopTabMode = 'workspace' | 'character_lab' | 'swift_source';

interface MacMenuBarProps {
  activeStatus: AgentStatus;
  activePack: CharacterPack;
  quota: QuotaState;
  urgentSubTask?: SubAgentTask;
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
  urgentSubTask,
  isPopoverOpen,
  onTogglePopover,
  isRefreshingQuota,
  activeDesktopTab,
  onSelectDesktopTab,
}) => {
  const [isStatusHovered, setIsStatusHovered] = useState<boolean>(false);
  const statusInfo = STATUS_META[activeStatus];

  return (
    <header className="sticky top-0 z-40 flex h-8 w-full items-center justify-between gap-8 border-b border-black/[0.05] bg-white/72 px-5 backdrop-blur-2xl select-none">
      {/* Zone 1: Minimalist Single-Line Brand Wordmark */}
      <a
        href="#top"
        onClick={(e) => {
          e.preventDefault();
          onSelectDesktopTab('workspace');
        }}
        className="text-[13px] font-semibold tracking-tight text-slate-900 whitespace-nowrap shrink-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-500 rounded"
      >
         AgentSpur
      </a>

      {/* Zone 2: Featherlight Single-Line Nav Links */}
      <nav className="hidden md:flex items-center gap-6 text-xs font-medium text-slate-500">
        {(
          [
            { id: 'workspace', label: '终端联动' },
            { id: 'character_lab', label: '灵动角色' },
            { id: 'swift_source', label: '原生源码' },
          ] as const
        ).map((item) => (
          <button
            key={item.id}
            type="button"
            onClick={() => onSelectDesktopTab(item.id)}
            className={`transition-colors duration-150 whitespace-nowrap shrink-0 hover:text-slate-900 underline-offset-4 ${
              activeDesktopTab === item.id
                ? 'text-slate-900 font-semibold underline'
                : 'text-slate-500'
            }`}
          >
            {item.label}
          </button>
        ))}
      </nav>

      {/* Zone 3: Fluid macOS NSStatusItem + Minimalist Hover Tooltip */}
      <div
        className="relative flex items-center shrink-0"
        onMouseEnter={() => setIsStatusHovered(true)}
        onMouseLeave={() => setIsStatusHovered(false)}
      >
        <button
          type="button"
          onClick={onTogglePopover}
          onFocus={() => setIsStatusHovered(true)}
          onBlur={() => setIsStatusHovered(false)}
          aria-expanded={isPopoverOpen}
          aria-describedby={
            isStatusHovered && urgentSubTask ? 'menubar-urgent-tooltip' : undefined
          }
          className={`flex items-center gap-2 rounded-full px-2.5 py-0.5 text-xs transition-colors duration-150 whitespace-nowrap shrink-0 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-500 ${
            isPopoverOpen
              ? 'bg-slate-900/[0.07] text-slate-950'
              : 'hover:bg-slate-900/[0.05] text-slate-800'
          }`}
        >
          <AgentSpriteCanvas status={activeStatus} pack={activePack} size={18} />

          <AnimatePresence mode="wait" initial={false}>
            <motion.span
              key={activeStatus}
              initial={{ opacity: 0, y: 3 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -3 }}
              transition={{ duration: 0.14, ease: [0.16, 1, 0.3, 1] }}
              className={`font-semibold ${statusInfo.textClass}`}
            >
              {statusInfo.label}
            </motion.span>
          </AnimatePresence>

          <span className="text-slate-300" aria-hidden="true">
            ·
          </span>
          <span className="font-mono tabular-nums text-slate-800">
            ${quota.remainingUsd.toFixed(2)}
          </span>
          <span className="text-slate-300" aria-hidden="true">
            ·
          </span>
          <span className="font-mono tabular-nums text-slate-500">
            {quota.resetTimeLabel.replace('重置', '')}
          </span>
          {isRefreshingQuota && (
            <RefreshCw className="w-3 h-3 text-sky-600 animate-spin shrink-0" />
          )}
        </button>

        {/* Minimalist Hover Tooltip: Most Urgent Sub-Task Name & TargetApp */}
        <AnimatePresence>
          {isStatusHovered && urgentSubTask && (
            <motion.div
              id="menubar-urgent-tooltip"
              role="tooltip"
              initial={{ opacity: 0, y: -4, scale: 0.98 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: -3, scale: 0.98 }}
              transition={{ duration: 0.14, ease: [0.16, 1, 0.3, 1] }}
              className="pointer-events-none absolute right-0 top-full mt-2 z-50 min-w-[200px] max-w-[280px] rounded-xl border border-black/[0.07] bg-white/95 px-3 py-2 shadow-[0_12px_30px_-6px_rgba(15,23,42,0.14)] backdrop-blur-2xl"
            >
              <div className="flex items-center justify-between gap-3 text-[10px] text-slate-400">
                <span
                  className={`font-medium ${STATUS_META[urgentSubTask.status].textClass}`}
                >
                  最急子任务 · {STATUS_META[urgentSubTask.status].label}
                </span>
                <span className="font-mono text-slate-500 whitespace-nowrap">
                  {urgentSubTask.targetApp}
                </span>
              </div>
              <div className="mt-0.5 truncate text-xs font-medium text-slate-900">
                {urgentSubTask.title}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </header>
  );
};
