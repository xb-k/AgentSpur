import React, { useRef, useState } from 'react';
import { ArrowUpRight, Bell, BellOff, FolderOpen, RefreshCw } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import {
  AgentStatus,
  CharacterPack,
  MasterSession,
  QuotaState,
  TargetApp,
} from '../types/agent';
import { STATUS_META } from '../data/initialData';
import { formatLiveStateTimerLabel } from '../utils/opencodeDb';
import { AgentSpriteCanvas } from './AgentSpriteCanvas';
import { AgentSpurLogo } from './AgentSpurLogo';
import { FeatherSwitch } from './FeatherSwitch';

type GroupFilter = 'all' | 'pending' | 'running' | 'completed';

interface StatusPopoverProps {
  isOpen: boolean;
  activeStatus: AgentStatus;
  sessions: MasterSession[];
  quota: QuotaState;
  isRefreshingQuota: boolean;
  onRefreshQuota: () => void;
  silentAlertEnabled: boolean;
  onToggleSilentAlert: () => void;
  packs: CharacterPack[];
  activePack: CharacterPack;
  onSelectPack: (packId: string) => void;
  onImportPackFile: (file: File) => void;
  selectedSessionId: string;
  selectedSubTaskId?: string;
  autoFocusedSubTaskIds?: ReadonlySet<string>;
  nowMs: number;
  onJumpToSession: (sessionId: string, subTaskId?: string) => void;
}

export const StatusPopover: React.FC<StatusPopoverProps> = ({
  isOpen,
  activeStatus,
  sessions,
  quota,
  isRefreshingQuota,
  onRefreshQuota,
  silentAlertEnabled,
  onToggleSilentAlert,
  packs,
  activePack,
  onSelectPack,
  onImportPackFile,
  selectedSessionId,
  selectedSubTaskId,
  autoFocusedSubTaskIds,
  nowMs,
  onJumpToSession,
}) => {
  const [groupFilter, setGroupFilter] = useState<GroupFilter>('all');
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const pendingSessions = sessions.filter((s) => s.status === AgentStatus.Confirm);
  const runningSessions = sessions.filter(
    (s) => s.status === AgentStatus.Thinking || s.status === AgentStatus.Working
  );
  const completedSessions = sessions.filter(
    (s) => s.status === AgentStatus.Completed || s.status === AgentStatus.Error
  );

  const activeSubAgents = sessions.reduce(
    (acc, s) =>
      acc +
      s.subTasks.filter(
        (sub) =>
          sub.status === AgentStatus.Working ||
          sub.status === AgentStatus.Thinking ||
          sub.status === AgentStatus.Confirm
      ).length,
    0
  );

  const groups: Array<{
    key: Exclude<GroupFilter, 'all'>;
    title: string;
    items: MasterSession[];
  }> = [
    { key: 'pending', title: '待处理', items: pendingSessions },
    { key: 'running', title: '运行中', items: runningSessions },
    { key: 'completed', title: '已完成', items: completedSessions },
  ];

  const visibleGroups =
    groupFilter === 'all' ? groups : groups.filter((g) => g.key === groupFilter);

  const statusMeta = STATUS_META[activeStatus];

  return (
    <AnimatePresence initial={false}>
      {isOpen && (
        <motion.aside
          aria-label="macOS 状态栏只读面板"
          initial={{ opacity: 0, y: -6, scale: 0.985 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: -6, scale: 0.985 }}
          transition={{ duration: 0.16, ease: [0.16, 1, 0.3, 1] }}
          className="w-full lg:w-[356px] shrink-0 rounded-2xl border border-black/[0.06] bg-white/82 shadow-[0_24px_60px_-15px_rgba(15,23,42,0.12)] backdrop-blur-3xl overflow-hidden select-none text-slate-900"
        >
          {/* Minimalist Header: AgentSpur Brand + Live 15 FPS Sprite + Quota ⌘R */}
          <div className="px-4 pt-3.5 pb-3 border-b border-black/[0.05]">
            <div className="flex items-center justify-between gap-3">
              <div className="flex items-center gap-2.5 min-w-0">
                <AgentSpriteCanvas
                  status={activeStatus}
                  pack={activePack}
                  size={24}
                />
                <div className="min-w-0">
                  <div className="flex items-center gap-1.5 text-[13px] font-semibold text-slate-900">
                    <AgentSpurLogo size={15} />
                    <span>AgentSpur</span>
                    <span className="text-slate-300" aria-hidden="true">
                      ·
                    </span>
                    <span className={statusMeta.textClass}>{statusMeta.label}</span>
                  </div>
                  <div className="text-[11px] text-slate-400 tabular-nums">
                    opencode.db · Master {sessions.length} · 子任务 {activeSubAgents} 活跃
                  </div>
                </div>
              </div>

              <button
                type="button"
                onClick={onRefreshQuota}
                title="刷新本机额度 (⌘R)"
                className="inline-flex items-center gap-1 rounded-lg border border-slate-200/80 bg-white/80 px-2 py-0.5 text-[11px] font-mono text-slate-500 shadow-[0_1px_2px_rgba(15,23,42,0.03)] hover:bg-white hover:text-sky-700 hover:border-sky-300/60 transition-all duration-150 whitespace-nowrap shrink-0 cursor-pointer"
              >
                <RefreshCw
                  className={`w-3 h-3 shrink-0 ${
                    isRefreshingQuota ? 'animate-spin text-sky-500' : ''
                  }`}
                />
                <span>⌘R</span>
              </button>
            </div>

            {/* Quiet One-Line Quota Info */}
            <div className="mt-2 flex items-center justify-between text-[11px] text-slate-500 font-mono tabular-nums">
              <span>
                余额 <strong className="font-semibold text-slate-800">${quota.remainingUsd.toFixed(2)}</strong> / ${quota.totalUsd.toFixed(0)}
              </span>
              <span>
                {quota.resetTimeLabel} ({quota.resetCountdown})
              </span>
            </div>
          </div>

          {/* Fluid Sliding Segmented Control */}
          <div className="px-3.5 pt-2.5 pb-1.5">
            <div
              role="tablist"
              aria-label="会话分组筛选"
              className="grid grid-cols-4 gap-0.5 rounded-xl border border-slate-200/70 bg-slate-100/70 p-0.5"
            >
              {(
                [
                  { id: 'all', label: '全部' },
                  { id: 'pending', label: `待处理 ${pendingSessions.length}` },
                  { id: 'running', label: `运行中 ${runningSessions.length}` },
                  { id: 'completed', label: `已完成 ${completedSessions.length}` },
                ] as const
              ).map((tab) => {
                const active = groupFilter === tab.id;
                return (
                  <button
                    key={tab.id}
                    role="tab"
                    type="button"
                    aria-selected={active}
                    onClick={() => setGroupFilter(tab.id)}
                    className={`relative rounded-[9px] py-1 px-1.5 text-[11px] font-medium tabular-nums transition-colors whitespace-nowrap shrink-0 cursor-pointer ${
                      active
                        ? 'text-sky-950'
                        : 'text-slate-500 hover:text-slate-800'
                    }`}
                  >
                    {active && (
                      <motion.span
                        layoutId="popoverGroupTab"
                        transition={{ duration: 0.16, ease: [0.16, 1, 0.3, 1] }}
                        className="absolute inset-0 rounded-[9px] bg-white shadow-[0_1px_3px_rgba(15,23,42,0.06)] ring-1 ring-slate-900/[0.04]"
                      />
                    )}
                    <span className="relative z-10">{tab.label}</span>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Featherlight Borderless Session Hierarchy (Zero Nested Cards) */}
          <div className="max-h-[400px] overflow-y-auto px-2.5 pb-2.5 space-y-3">
            {visibleGroups.map((group) => (
              <section key={group.key} className="space-y-0.5">
                <div className="px-2 pt-1.5 pb-0.5 flex items-center justify-between text-[10px] font-medium text-slate-400">
                  <span>{group.title}</span>
                  <span className="font-mono tabular-nums">{group.items.length}</span>
                </div>

                {group.items.length === 0 ? (
                  <div className="px-2 py-2.5 text-center text-xs text-slate-400">
                    暂无会话
                  </div>
                ) : (
                  <div className="space-y-1">
                    {group.items.map((session) => {
                      const isMasterSelected =
                        selectedSessionId === session.id && !selectedSubTaskId;
                      const sMeta = STATUS_META[session.status];

                      return (
                        <div key={session.id}>
                          {/* Master Row */}
                          <button
                            type="button"
                            onClick={() => onJumpToSession(session.id)}
                            className={`group w-full text-left rounded-lg px-2 py-1.5 transition-colors duration-150 flex items-start gap-2 ${
                              isMasterSelected
                                ? 'bg-sky-500/[0.09]'
                                : 'hover:bg-black/[0.035]'
                            }`}
                          >
                            <div className="mt-0.5 shrink-0">
                              <AgentSpriteCanvas
                                status={session.status}
                                pack={activePack}
                                size={16}
                              />
                            </div>

                            <div className="min-w-0 flex-1">
                              <div className="flex items-center justify-between gap-1.5">
                                <span className="truncate text-xs font-medium text-slate-900 group-hover:text-sky-700 transition-colors">
                                  {session.title}
                                </span>
                                <div className="flex items-center gap-1.5 shrink-0">
                                  {(session.status === AgentStatus.Completed ||
                                    group.key === 'completed') &&
                                    session.duration && (
                                      <span className="font-mono text-[10px] tabular-nums text-slate-400">
                                        总耗时 {session.duration}
                                      </span>
                                    )}
                                  <ArrowUpRight className="w-3 h-3 text-slate-300 opacity-0 group-hover:opacity-100 group-hover:text-sky-600 shrink-0 transition-opacity" />
                                </div>
                              </div>

                              <div className="mt-0.5 flex items-center gap-1.5 text-[11px] text-slate-400">
                                <span
                                  title={`opencode.db · ${session.dbRecordRef}`}
                                  className={`font-mono tabular-nums whitespace-nowrap shrink-0 ${sMeta.textClass}`}
                                >
                                  {formatLiveStateTimerLabel(
                                    session.status,
                                    session.stateEnteredAt,
                                    nowMs
                                  )}
                                </span>
                                <span aria-hidden="true">·</span>
                                <span className="truncate">{session.targetRef}</span>
                              </div>
                            </div>
                          </button>

                          {/* Whisper-light Nested Sub-Agents */}
                          {session.subTasks.length > 0 && (
                            <div className="ml-4 pl-2.5 border-l border-slate-200/80 space-y-1 my-1">
                              {session.subTasks.map((sub) => {
                                const isSubSelected =
                                  selectedSessionId === session.id &&
                                  selectedSubTaskId === sub.id;
                                const isAutoFocused = Boolean(
                                  autoFocusedSubTaskIds?.has(sub.id)
                                );
                                const subMeta = STATUS_META[sub.status];

                                return (
                                  <button
                                    key={sub.id}
                                    type="button"
                                    onClick={() =>
                                      onJumpToSession(session.id, sub.id)
                                    }
                                    title={`opencode.db · ${sub.dbRecordRef}`}
                                    className={`group w-full text-left rounded-md px-2 py-1 flex items-center gap-1.5 transition-colors duration-150 ${
                                      isAutoFocused
                                        ? 'animate-focus-border bg-sky-500/[0.12] text-slate-950 font-medium'
                                        : isSubSelected
                                        ? 'border border-transparent bg-sky-500/[0.09] text-slate-950'
                                        : 'border border-transparent hover:bg-black/[0.03]'
                                    }`}
                                  >
                                    <AgentSpriteCanvas
                                      status={sub.status}
                                      pack={activePack}
                                      size={14}
                                    />
                                    <span
                                      className={`min-w-0 flex-1 truncate text-[11px] ${
                                        isAutoFocused
                                          ? 'text-sky-950 font-semibold'
                                          : 'text-slate-600 group-hover:text-slate-900'
                                      }`}
                                    >
                                      {sub.title}
                                    </span>
                                    {(sub.status === AgentStatus.Completed ||
                                      group.key === 'completed') && (
                                      <span className="font-mono text-[10px] tabular-nums text-slate-400 shrink-0 whitespace-nowrap">
                                        耗时 {sub.elapsed}
                                      </span>
                                    )}
                                    <span
                                      className={`font-mono tabular-nums text-[10px] shrink-0 whitespace-nowrap ${subMeta.textClass}`}
                                    >
                                      {formatLiveStateTimerLabel(
                                        sub.status,
                                        sub.stateEnteredAt,
                                        nowMs
                                      )}
                                    </span>
                                    <span className="text-[10px] font-mono text-slate-400 group-hover:text-sky-600 shrink-0 whitespace-nowrap">
                                      {sub.targetApp === TargetApp.OpenCodeTUI
                                        ? 'TUI'
                                        : `Tab${(sub.itermTabIndex ?? 0) + 1}`}
                                    </span>
                                  </button>
                                );
                              })}
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                )}
              </section>
            ))}
          </div>

          {/* Ultra-Minimal Single-Zone Preferences Footer */}
          <div className="border-t border-black/[0.05] px-3.5 py-2.5 flex items-center justify-between gap-2 text-[11px]">
            <div className="flex items-center gap-2 shrink-0">
              <FeatherSwitch
                size="sm"
                checked={silentAlertEnabled}
                onChange={onToggleSilentAlert}
                ariaLabel="切换任务完成静音通知"
                title="任务跑完弹出静音通知，可随时关闭"
              />
              <span
                className={`inline-flex items-center gap-1 font-medium transition-colors whitespace-nowrap ${
                  silentAlertEnabled ? 'text-slate-700' : 'text-slate-400'
                }`}
              >
                {silentAlertEnabled ? (
                  <BellOff className="w-3 h-3 text-sky-500 shrink-0" />
                ) : (
                  <Bell className="w-3 h-3 opacity-60 shrink-0" />
                )}
                <span>静音通知</span>
              </span>
            </div>

            <div className="flex items-center gap-1.5 min-w-0">
              <select
                aria-label="切换 DeepSeek 角色包"
                value={activePack.id}
                onChange={(e) => onSelectPack(e.target.value)}
                className="max-w-[126px] truncate rounded-lg border border-slate-200/80 bg-white/80 hover:bg-white hover:border-sky-300/60 px-2 py-1 text-[11px] font-medium text-slate-700 shadow-[0_1px_2px_rgba(15,23,42,0.03)] focus:outline-none focus:ring-2 focus:ring-sky-400/30 transition-all cursor-pointer"
              >
                {packs.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>

              <input
                ref={fileInputRef}
                type="file"
                accept=".json,application/json"
                className="hidden"
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) {
                    onImportPackFile(file);
                    e.target.value = '';
                  }
                }}
              />

              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                title="导入自制 DeepSeek 角色包 (.json)"
                className="inline-flex items-center gap-1 rounded-lg border border-sky-300/55 bg-sky-500/[0.08] px-2 py-1 font-medium text-sky-700 shadow-[0_1px_2px_rgba(14,165,233,0.05)] hover:bg-sky-500/[0.14] hover:border-sky-400/60 transition-all duration-150 whitespace-nowrap shrink-0 cursor-pointer"
              >
                <FolderOpen className="w-3 h-3 shrink-0" />
                <span>导入</span>
              </button>
            </div>
          </div>
        </motion.aside>
      )}
    </AnimatePresence>
  );
};
