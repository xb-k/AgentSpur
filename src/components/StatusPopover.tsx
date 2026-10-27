import React, { useRef, useState } from 'react';
import {
  ArrowUpRight,
  Bell,
  BellOff,
  FolderOpen,
  RefreshCw,
  SquareTerminal,
  Terminal,
} from 'lucide-react';
import {
  AgentStatus,
  CharacterPack,
  MasterSession,
  QuotaState,
  TargetApp,
} from '../types/agent';
import { STATUS_META } from '../data/initialData';
import { AgentSpriteCanvas } from './AgentSpriteCanvas';

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
  onJumpToSession,
}) => {
  const [groupFilter, setGroupFilter] = useState<GroupFilter>('all');
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  if (!isOpen) return null;

  const pendingSessions = sessions.filter((s) => s.status === AgentStatus.Confirm);
  const runningSessions = sessions.filter(
    (s) => s.status === AgentStatus.Thinking || s.status === AgentStatus.Working
  );
  const completedSessions = sessions.filter(
    (s) => s.status === AgentStatus.Completed || s.status === AgentStatus.Error
  );

  const totalSubAgents = sessions.reduce((acc, s) => acc + s.subTasks.length, 0);
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

  const quotaRatio = Math.max(
    0,
    Math.min(100, Math.round((quota.remainingUsd / quota.totalUsd) * 100))
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
    <aside
      aria-label="macOS 状态栏只读预览面板"
      className="w-full lg:w-[410px] shrink-0 rounded-xl border border-slate-200/90 bg-white/92 shadow-[0_20px_50px_rgba(15,23,42,0.12)] backdrop-blur-2xl overflow-hidden select-none text-slate-900"
    >
      {/* Top Header: Master + Sub-Agent Live Readout */}
      <div className="flex items-center justify-between gap-3 px-4 py-3.5 border-b border-slate-200/80">
        <div className="flex items-center gap-3 min-w-0">
          <AgentSpriteCanvas status={activeStatus} pack={activePack} size={28} />
          <div className="min-w-0">
            <div className="flex items-center gap-1.5 text-sm font-semibold text-slate-900">
              <span className={statusMeta.textClass}>{statusMeta.label}</span>
              <span className="text-slate-300" aria-hidden="true">
                ·
              </span>
              <span className="truncate text-slate-700 font-medium">
                {statusMeta.shortVerb}
              </span>
            </div>
            <div className="mt-0.5 flex items-center gap-1.5 text-[11px] text-slate-500 tabular-nums">
              <span>Master {sessions.length}</span>
              <span aria-hidden="true">·</span>
              <span>
                子 Agent {activeSubAgents}/{totalSubAgents} 活跃
              </span>
              <span aria-hidden="true">·</span>
              <span className="font-mono">15 FPS</span>
            </div>
          </div>
        </div>

        <span className="text-[11px] text-slate-500 whitespace-nowrap shrink-0">
          仅展示看
        </span>
      </div>

      {/* Quota & ⌘R Refresh Strip */}
      <div className="px-4 py-2.5 border-b border-slate-200/80 bg-slate-50/70">
        <div className="flex items-center justify-between gap-2 text-xs">
          <div className="flex items-center gap-1.5 text-slate-800 tabular-nums font-mono">
            <span className="font-medium">剩余 ${quota.remainingUsd.toFixed(2)}</span>
            <span className="text-slate-400" aria-hidden="true">
              /
            </span>
            <span className="text-slate-500">${quota.totalUsd.toFixed(2)}</span>
            <span className="text-slate-400" aria-hidden="true">
              ·
            </span>
            <span className="text-slate-600">
              {quota.resetTimeLabel} ({quota.resetCountdown})
            </span>
          </div>

          <button
            type="button"
            onClick={onRefreshQuota}
            title="刷新本机额度缓存 (快捷键 ⌘R)"
            className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-[11px] font-medium text-slate-700 hover:bg-slate-200/70 hover:text-slate-950 transition-colors duration-150 whitespace-nowrap shrink-0"
          >
            <RefreshCw
              className={`w-3 h-3 shrink-0 ${
                isRefreshingQuota ? 'animate-spin text-sky-600' : ''
              }`}
            />
            <span className="font-mono">⌘R</span>
          </button>
        </div>

        {/* Hairline Quota Bar */}
        <div className="mt-2 h-1 w-full rounded-full bg-slate-200/90 overflow-hidden">
          <div
            className={`h-full rounded-full transition-opacity duration-150 ${
              quotaRatio > 25 ? 'bg-sky-600' : 'bg-amber-500'
            } ${
              quotaRatio >= 70
                ? 'w-3/4'
                : quotaRatio >= 50
                ? 'w-2/3'
                : quotaRatio >= 30
                ? 'w-1/2'
                : 'w-1/4'
            }`}
          />
        </div>
      </div>

      {/* Interactive Segmented Group Filter */}
      <div className="px-4 pt-3 pb-2 flex items-center justify-between gap-2">
        <div
          role="tablist"
          aria-label="opencode 会话分组筛选"
          className="grid grid-cols-4 gap-1 w-full rounded-lg bg-slate-200/70 p-0.5"
        >
          {(
            [
              { id: 'all', label: `全部 ${sessions.length}` },
              { id: 'pending', label: `待处理 ${pendingSessions.length}` },
              { id: 'running', label: `运行中 ${runningSessions.length}` },
              { id: 'completed', label: `已完成 ${completedSessions.length}` },
            ] as const
          ).map((tab) => (
            <button
              key={tab.id}
              role="tab"
              type="button"
              aria-selected={groupFilter === tab.id}
              onClick={() => setGroupFilter(tab.id)}
              className={`rounded-md py-1 px-2 text-[11px] font-medium tabular-nums transition-colors duration-150 whitespace-nowrap shrink-0 ${
                groupFilter === tab.id
                  ? 'bg-white text-slate-900 shadow-xs'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {/* Grouped Master + Nested opencode Sub-Agent Tree (Read-Only Click-to-Jump) */}
      <div className="max-h-[410px] overflow-y-auto px-3 pb-3 space-y-3">
        {visibleGroups.map((group) => (
          <section key={group.key} className="space-y-1">
            <div className="flex items-center justify-between px-1.5 pt-1 text-[11px] font-semibold text-slate-500">
              <span>{group.title}</span>
              <span className="font-mono tabular-nums font-normal">
                {group.items.length} 项
              </span>
            </div>

            {group.items.length === 0 ? (
              <div className="px-2 py-3 text-center text-xs text-slate-400">
                当前分组暂无本机 opencode 会话记录
              </div>
            ) : (
              <div className="space-y-1.5">
                {group.items.map((session) => {
                  const isMasterSelected =
                    selectedSessionId === session.id && !selectedSubTaskId;
                  const sMeta = STATUS_META[session.status];

                  return (
                    <div
                      key={session.id}
                      className="rounded-lg border border-slate-200/85 bg-white overflow-hidden"
                    >
                      {/* Master Task Row — Click jumps straight to opencode TUI or iTerm2 */}
                      <button
                        type="button"
                        onClick={() => onJumpToSession(session.id)}
                        className={`group w-full text-left px-2.5 py-2 transition-colors duration-150 flex items-start gap-2.5 ${
                          isMasterSelected
                            ? 'bg-sky-50'
                            : 'hover:bg-slate-50'
                        }`}
                      >
                        <div className="mt-0.5 shrink-0">
                          <AgentSpriteCanvas
                            status={session.status}
                            pack={activePack}
                            size={18}
                          />
                        </div>

                        <div className="min-w-0 flex-1">
                          <div className="flex items-center justify-between gap-2">
                            <span className="truncate text-xs font-semibold text-slate-900 group-hover:text-sky-800">
                              {session.title}
                            </span>
                            <ArrowUpRight className="w-3.5 h-3.5 text-slate-400 group-hover:text-sky-600 shrink-0 transition-colors" />
                          </div>

                          <div className="mt-1 flex items-center gap-1.5 text-[11px] text-slate-500">
                            <span className={`font-medium ${sMeta.textClass}`}>
                              {sMeta.label}
                            </span>
                            <span aria-hidden="true">·</span>
                            <span className="truncate max-w-[115px]">
                              Master ({session.modelName.replace('deepseek/', '')})
                            </span>
                            <span aria-hidden="true">·</span>
                            <span className="inline-flex items-center gap-1 truncate text-slate-600">
                              {session.targetApp === TargetApp.OpenCodeTUI ? (
                                <SquareTerminal className="w-3 h-3 text-slate-500 shrink-0" />
                              ) : (
                                <Terminal className="w-3 h-3 text-slate-500 shrink-0" />
                              )}
                              <span className="truncate">{session.targetRef}</span>
                            </span>
                          </div>
                        </div>
                      </button>

                      {/* Indented opencode Sub-Tasks Mounted Under Master Task */}
                      {session.subTasks.length > 0 && (
                        <div className="border-t border-slate-100 bg-slate-50/75 py-1">
                          {session.subTasks.map((sub, idx) => {
                            const isLast = idx === session.subTasks.length - 1;
                            const isSubSelected =
                              selectedSessionId === session.id &&
                              selectedSubTaskId === sub.id;
                            const subMeta = STATUS_META[sub.status];

                            return (
                              <button
                                key={sub.id}
                                type="button"
                                onClick={() => onJumpToSession(session.id, sub.id)}
                                className={`group w-full text-left pl-4 pr-2.5 py-1.5 flex items-center gap-2 transition-colors duration-150 ${
                                  isSubSelected
                                    ? 'bg-sky-100/70 text-slate-950'
                                    : 'hover:bg-slate-200/50'
                                }`}
                              >
                                <span
                                  aria-hidden="true"
                                  className="font-mono text-xs text-slate-400 shrink-0 select-none"
                                >
                                  {isLast ? '└─' : '├─'}
                                </span>

                                <AgentSpriteCanvas
                                  status={sub.status}
                                  pack={activePack}
                                  size={14}
                                />

                                <span className="min-w-0 flex-1 truncate text-[11px] text-slate-700 group-hover:text-slate-950">
                                  {sub.title}
                                </span>

                                <span
                                  className={`text-[10px] font-medium shrink-0 whitespace-nowrap ${subMeta.textClass}`}
                                >
                                  {subMeta.label}
                                </span>

                                <span className="text-slate-300 text-[10px]" aria-hidden="true">
                                  ·
                                </span>

                                <span className="text-[10px] font-mono text-slate-500 group-hover:text-sky-700 shrink-0 whitespace-nowrap">
                                  {sub.targetApp === TargetApp.OpenCodeTUI
                                    ? 'opencode'
                                    : `iTerm#${(sub.itermTabIndex ?? 0) + 1}`}
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

      {/* Compact Footer Preferences: Silent Completion Alert + DeepSeek Role Pack Switcher */}
      <div className="border-t border-slate-200/80 bg-slate-50/90 px-4 py-3 space-y-2.5">
        <div className="flex items-center justify-between gap-2 text-xs">
          <span className="text-slate-700 font-medium">任务跑完静音通知</span>
          <button
            type="button"
            role="switch"
            aria-checked={silentAlertEnabled}
            onClick={onToggleSilentAlert}
            className={`inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-[11px] font-medium transition-colors duration-150 whitespace-nowrap shrink-0 ${
              silentAlertEnabled
                ? 'bg-emerald-100 text-emerald-800 hover:bg-emerald-200/80'
                : 'bg-slate-200/80 text-slate-600 hover:text-slate-900'
            }`}
          >
            {silentAlertEnabled ? (
              <>
                <BellOff className="w-3 h-3 shrink-0" />
                <span>静音提醒已开</span>
              </>
            ) : (
              <>
                <Bell className="w-3 h-3 shrink-0 opacity-60" />
                <span>提醒已关闭</span>
              </>
            )}
          </button>
        </div>

        <div className="flex items-center justify-between gap-2 text-xs">
          <label
            htmlFor="deepseek-pack-select"
            className="text-slate-700 font-medium shrink-0"
          >
            DeepSeek 角色
          </label>
          <div className="flex items-center gap-1.5 min-w-0 flex-1 justify-end">
            <select
              id="deepseek-pack-select"
              value={activePack.id}
              onChange={(e) => onSelectPack(e.target.value)}
              className="max-w-[168px] truncate rounded-md border border-slate-300 bg-white px-2 py-1 text-[11px] text-slate-800 focus:outline-none focus:ring-1 focus:ring-sky-600"
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
              title="导入本地自制 DeepSeek 角色包 (.json)"
              className="inline-flex items-center gap-1 rounded-md border border-slate-300 bg-white px-2 py-1 text-[11px] font-medium text-slate-700 hover:bg-slate-100 transition-colors duration-150 whitespace-nowrap shrink-0"
            >
              <FolderOpen className="w-3 h-3 shrink-0" />
              <span>导入包</span>
            </button>
          </div>
        </div>

        <div className="pt-1 border-t border-slate-200/70 flex items-center justify-between text-[10px] text-slate-500">
          <span>原生 AppKit · 无 WebView · 零常驻进程</span>
          <span className="font-mono">本机只读 O_RDONLY</span>
        </div>
      </div>
    </aside>
  );
};
