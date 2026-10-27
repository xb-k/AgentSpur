import React, { useEffect, useRef, useState } from 'react';
import { Check, Copy, Download, FolderOpen, RotateCcw } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import {
  AgentStatus,
  CharacterPack,
  MasterSession,
  SubAgentTask,
} from '../types/agent';
import {
  NATIVE_SWIFT_APPKIT_CODE,
  NATIVE_SWIFT_PACKAGE_CODE,
  SAMPLE_CUSTOM_PACK_JSON,
  STATUS_META,
} from '../data/initialData';
import {
  AgentSpriteCanvas,
  subscribeGlobalFrameIndex,
} from './AgentSpriteCanvas';
import { formatLiveStateTimerLabel } from '../utils/opencodeDb';
import { DesktopTabMode } from './MacMenuBar';

interface DesktopWorkspaceProps {
  activeTab: DesktopTabMode;
  onChangeTab: (tab: DesktopTabMode) => void;
  sessions: MasterSession[];
  selectedSession: MasterSession;
  selectedSubTask?: SubAgentTask;
  lastJumpNotice: string | null;
  activePack: CharacterPack;
  packs: CharacterPack[];
  onSelectPack: (packId: string) => void;
  onImportPackObject: (pack: CharacterPack) => void;
  onImportPackFile: (file: File) => void;
  onUpdateSessionStatus: (
    sessionId: string,
    nextStatus: AgentStatus,
    subTaskId?: string
  ) => void;
  autoFocusedSubTaskIds?: ReadonlySet<string>;
  nowMs: number;
  onSelectSessionFromDesktop: (sessionId: string, subTaskId?: string) => void;
}

const ITERM_TABS = [
  { index: 0, label: 'opencode · main' },
  { index: 1, label: 'opencode · @explore' },
  { index: 2, label: 'opencode · tty' },
  { index: 3, label: 'opencode · log' },
];

export const DesktopWorkspace: React.FC<DesktopWorkspaceProps> = ({
  activeTab,
  sessions,
  selectedSession,
  selectedSubTask,
  lastJumpNotice,
  activePack,
  packs,
  onSelectPack,
  onImportPackObject,
  onImportPackFile,
  onUpdateSessionStatus,
  autoFocusedSubTaskIds,
  nowMs,
  onSelectSessionFromDesktop,
}) => {
  const [inspectedState, setInspectedState] = useState<AgentStatus>(
    AgentStatus.Working
  );
  const [liveFrameIdx, setLiveFrameIdx] = useState<number>(0);
  const [copiedSwift, setCopiedSwift] = useState<boolean>(false);
  const [swiftFileTab, setSwiftFileTab] = useState<'main' | 'package'>('main');

  const [customName, setCustomName] = useState<string>('自制微星精灵');
  const [customModel, setCustomModel] = useState<string>(
    'deepseek/deepseek-reasoner'
  );
  const [customGrid, setCustomGrid] = useState<string[]>(
    SAMPLE_CUSTOM_PACK_JSON.customBaseSprite
  );
  const fileUploadRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    if (activeTab !== 'character_lab') return;
    const unsub = subscribeGlobalFrameIndex((f) => setLiveFrameIdx(f));
    return unsub;
  }, [activeTab]);

  const activeTargetRef = selectedSubTask
    ? selectedSubTask.targetRef
    : selectedSession.targetRef;
  const activeStatus = selectedSubTask
    ? selectedSubTask.status
    : selectedSession.status;
  const activeStateEnteredAt = selectedSubTask
    ? selectedSubTask.stateEnteredAt
    : selectedSession.stateEnteredAt;
  const activeDbRecordRef = selectedSubTask
    ? selectedSubTask.dbRecordRef
    : selectedSession.dbRecordRef;
  const activeLogLines = selectedSubTask
    ? selectedSubTask.logLines
    : selectedSession.logLines;
  const activeItermIndex =
    (selectedSubTask ? selectedSubTask.itermTabIndex : selectedSession.itermTabIndex) ??
    0;
  const isSelectedSubTaskAutoFocused = Boolean(
    selectedSubTask && autoFocusedSubTaskIds?.has(selectedSubTask.id)
  );

  const handleDownloadSampleJson = () => {
    const payload = JSON.stringify(SAMPLE_CUSTOM_PACK_JSON, null, 2);
    const blob = new Blob([payload], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'deepseek-minimal-pack.json';
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleDownloadSwiftProject = () => {
    const content =
      swiftFileTab === 'main' ? NATIVE_SWIFT_APPKIT_CODE : NATIVE_SWIFT_PACKAGE_CODE;
    const filename = swiftFileTab === 'main' ? 'main.swift' : 'Package.swift';
    const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleCopySwift = async () => {
    const content =
      swiftFileTab === 'main' ? NATIVE_SWIFT_APPKIT_CODE : NATIVE_SWIFT_PACKAGE_CODE;
    try {
      await navigator.clipboard.writeText(content);
      setCopiedSwift(true);
      window.setTimeout(() => setCopiedSwift(false), 1600);
    } catch {
      // Ignore clipboard fallback
    }
  };

  const toggleGridCell = (r: number, c: number) => {
    setCustomGrid((prev) =>
      prev.map((row, rowIdx) => {
        if (rowIdx !== r) return row;
        const chars = row.split('');
        const curr = chars[c];
        chars[c] = curr === '.' ? '#' : curr === '#' ? '+' : '.';
        return chars.join('');
      })
    );
  };

  const handleApplyCustomPack = () => {
    const newPack: CharacterPack = {
      id: `custom-${Date.now()}`,
      name: `${customName.trim() || '自制角色'}`,
      author: 'Local Mac',
      version: '1.0.0',
      deepseekModel: customModel,
      roleDescription: '本地自制极简 15 FPS 角色包。',
      archetype: 'custom_pixel',
      primaryColor: '#0F172A',
      secondaryColor: '#0EA5E9',
      customBaseSprite: customGrid,
    };
    onImportPackObject(newPack);
  };

  if (activeTab === 'character_lab') {
    return (
      <motion.div
        key="character_lab"
        initial={{ opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.18, ease: [0.16, 1, 0.3, 1] }}
        className="flex-1 min-w-0 rounded-2xl border border-black/[0.06] bg-white/82 backdrop-blur-3xl shadow-[0_24px_60px_-15px_rgba(15,23,42,0.08)] overflow-hidden text-slate-900"
      >
        <div className="flex items-center justify-between gap-4 px-5 py-3.5 border-b border-black/[0.05]">
          <div className="flex items-center gap-2">
            <span className="w-2.5 h-2.5 rounded-full bg-rose-400" />
            <span className="w-2.5 h-2.5 rounded-full bg-amber-400" />
            <span className="w-2.5 h-2.5 rounded-full bg-emerald-400" />
            <h1 className="ml-2 text-xs font-semibold text-slate-800">
              AgentSpur · 灵动角色与 15 FPS 帧序列
            </h1>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleDownloadSampleJson}
              className="inline-flex items-center gap-1 rounded-xl border border-slate-200/80 bg-white/80 px-2.5 py-1 text-xs font-medium text-slate-600 shadow-[0_1px_2px_rgba(15,23,42,0.03)] hover:bg-white hover:text-slate-900 hover:border-slate-300/80 transition-all duration-150 whitespace-nowrap shrink-0 cursor-pointer"
            >
              <Download className="w-3.5 h-3.5 shrink-0" />
              <span>示例 JSON</span>
            </button>
            <input
              ref={fileUploadRef}
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
              onClick={() => fileUploadRef.current?.click()}
              className="inline-flex items-center gap-1.5 rounded-xl border border-sky-300/60 bg-sky-500/[0.09] px-3 py-1 text-xs font-medium text-sky-700 shadow-[0_1px_2px_rgba(14,165,233,0.06)] hover:bg-sky-500/[0.15] hover:border-sky-400/60 transition-all duration-150 whitespace-nowrap shrink-0 cursor-pointer"
            >
              <FolderOpen className="w-3.5 h-3.5 shrink-0" />
              <span>导入角色包</span>
            </button>
          </div>
        </div>

        <div className="p-6 space-y-8">
          {/* 5 States Simultaneous 15 FPS Strip */}
          <section className="space-y-3">
            <div className="flex items-baseline justify-between gap-2">
              <h2 className="text-sm font-semibold text-slate-900">
                五状态实时预览
              </h2>
              <span className="text-[11px] font-mono text-slate-400 tabular-nums">
                {activePack.name} · 15 FPS · 帧 {String(liveFrameIdx + 1).padStart(2, '0')}/15
              </span>
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-5 gap-2.5">
              {(Object.values(AgentStatus) as AgentStatus[]).map((st) => {
                const meta = STATUS_META[st];
                const isSelected = inspectedState === st;
                return (
                  <button
                    key={st}
                    type="button"
                    onClick={() => setInspectedState(st)}
                    className={`relative flex flex-col items-center justify-center rounded-xl py-4 px-3 transition-colors duration-150 ${
                      isSelected
                        ? 'bg-sky-500/[0.08]'
                        : 'bg-slate-900/[0.025] hover:bg-slate-900/[0.045]'
                    }`}
                  >
                    <AgentSpriteCanvas status={st} pack={activePack} size={32} />
                    <span className={`mt-2 text-xs font-semibold ${meta.textClass}`}>
                      {meta.label}
                    </span>
                    <span className="mt-0.5 text-[11px] text-slate-400">
                      {meta.shortVerb}
                    </span>
                  </button>
                );
              })}
            </div>
          </section>

          {/* 15-Frame Minimalist Strip */}
          <section className="space-y-2.5 pt-4 border-t border-black/[0.05]">
            <div className="flex items-baseline justify-between gap-2">
              <h2 className="text-sm font-semibold text-slate-900">
                {STATUS_META[inspectedState].label} · 15 帧分解
              </h2>
              <span className="text-[11px] text-slate-400">
                {STATUS_META[inspectedState].frameNote}
              </span>
            </div>

            <div className="grid grid-cols-5 sm:grid-cols-15 gap-1">
              {Array.from({ length: 15 }, (_, idx) => {
                const isCurrentTick = liveFrameIdx === idx;
                return (
                  <div
                    key={idx}
                    className={`flex flex-col items-center justify-center rounded-lg py-2 px-1 transition-colors duration-75 ${
                      isCurrentTick
                        ? 'bg-sky-500/[0.12]'
                        : 'bg-slate-900/[0.02]'
                    }`}
                  >
                    <AgentSpriteCanvas
                      status={inspectedState}
                      pack={activePack}
                      size={20}
                      fixedFrame={idx}
                    />
                    <span className="mt-1 font-mono text-[10px] tabular-nums text-slate-400">
                      {String(idx + 1).padStart(2, '0')}
                    </span>
                  </div>
                );
              })}
            </div>
          </section>

          {/* Minimalist Role Switcher + Pixel Sketchpad */}
          <section className="grid grid-cols-1 xl:grid-cols-12 gap-8 pt-4 border-t border-black/[0.05] items-start">
            <div className="xl:col-span-6 space-y-2.5">
              <h2 className="text-sm font-semibold text-slate-900">切换角色</h2>
              <div className="space-y-1">
                {packs.map((pack) => {
                  const active = pack.id === activePack.id;
                  return (
                    <button
                      key={pack.id}
                      type="button"
                      onClick={() => onSelectPack(pack.id)}
                      className={`w-full text-left rounded-xl px-3 py-2.5 flex items-center gap-3 transition-colors duration-150 ${
                        active
                          ? 'bg-sky-500/[0.09]'
                          : 'hover:bg-slate-900/[0.035]'
                      }`}
                    >
                      <AgentSpriteCanvas
                        status={inspectedState}
                        pack={pack}
                        size={24}
                      />
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center justify-between gap-2">
                          <span className="text-xs font-semibold text-slate-900 truncate">
                            {pack.name}
                          </span>
                          <span className="font-mono text-[11px] text-slate-400 shrink-0">
                            {pack.deepseekModel.replace('deepseek/', '')}
                          </span>
                        </div>
                        <p className="mt-0.5 text-[11px] text-slate-500 truncate">
                          {pack.roleDescription}
                        </p>
                      </div>
                    </button>
                  );
                })}
              </div>
            </div>

            <div className="xl:col-span-6 space-y-3">
              <div className="flex items-center justify-between gap-2">
                <h2 className="text-sm font-semibold text-slate-900">
                  点阵自制角色
                </h2>
                <button
                  type="button"
                  onClick={() =>
                    setCustomGrid(SAMPLE_CUSTOM_PACK_JSON.customBaseSprite)
                  }
                  className="inline-flex items-center gap-1 rounded-lg border border-slate-200/80 bg-white/75 px-2 py-0.5 text-xs text-slate-500 hover:bg-white hover:text-slate-800 transition-all whitespace-nowrap shrink-0 cursor-pointer"
                >
                  <RotateCcw className="w-3 h-3" />
                  <span>重置</span>
                </button>
              </div>

              <div className="flex flex-col sm:flex-row gap-4 items-start">
                <div className="grid grid-cols-12 gap-0.5 p-2 rounded-xl border border-slate-200/70 bg-slate-100/70 shrink-0">
                  {customGrid.map((row, rIdx) =>
                    row.split('').map((cell, cIdx) => (
                      <button
                        key={`${rIdx}-${cIdx}`}
                        type="button"
                        onClick={() => toggleGridCell(rIdx, cIdx)}
                        aria-label={`像素 ${rIdx + 1},${cIdx + 1}`}
                        className={`w-3.5 h-3.5 rounded-[3px] transition-colors cursor-pointer ${
                          cell === '#'
                            ? 'bg-slate-700'
                            : cell === '+'
                            ? 'bg-sky-400'
                            : 'bg-white/85 hover:bg-white'
                        }`}
                      />
                    ))
                  )}
                </div>

                <div className="flex-1 space-y-2.5 w-full">
                  <input
                    type="text"
                    aria-label="自定义角色名称"
                    placeholder="角色名称"
                    value={customName}
                    onChange={(e) => setCustomName(e.target.value)}
                    className="w-full rounded-xl border border-slate-200/85 bg-white/85 px-3 py-1.5 text-xs text-slate-800 shadow-[0_1px_2px_rgba(15,23,42,0.03)] focus:bg-white focus:outline-none focus:ring-2 focus:ring-sky-400/30 focus:border-sky-400/60 transition-all"
                  />

                  <select
                    aria-label="绑定 DeepSeek 模型"
                    value={customModel}
                    onChange={(e) => setCustomModel(e.target.value)}
                    className="w-full rounded-xl border border-slate-200/85 bg-white/85 px-3 py-1.5 text-xs text-slate-800 shadow-[0_1px_2px_rgba(15,23,42,0.03)] focus:bg-white focus:outline-none focus:ring-2 focus:ring-sky-400/30 focus:border-sky-400/60 transition-all cursor-pointer"
                  >
                    <option value="deepseek/deepseek-reasoner">
                      deepseek/deepseek-reasoner
                    </option>
                    <option value="deepseek/deepseek-chat">
                      deepseek/deepseek-chat
                    </option>
                  </select>

                  <button
                    type="button"
                    onClick={handleApplyCustomPack}
                    className="w-full rounded-xl border border-sky-300/60 bg-sky-500/[0.09] px-3 py-1.5 text-xs font-medium text-sky-700 shadow-[0_1px_2px_rgba(14,165,233,0.06)] hover:bg-sky-500/[0.15] hover:border-sky-400/60 transition-all duration-150 whitespace-nowrap cursor-pointer"
                  >
                    载入到菜单栏
                  </button>
                </div>
              </div>
            </div>
          </section>
        </div>
      </motion.div>
    );
  }

  if (activeTab === 'swift_source') {
    return (
      <motion.div
        key="swift_source"
        initial={{ opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.18, ease: [0.16, 1, 0.3, 1] }}
        className="flex-1 min-w-0 rounded-2xl border border-black/[0.06] bg-white/82 backdrop-blur-3xl shadow-[0_24px_60px_-15px_rgba(15,23,42,0.08)] overflow-hidden text-slate-900"
      >
        <div className="flex items-center justify-between gap-4 px-5 py-3.5 border-b border-black/[0.05]">
          <div className="flex items-center gap-2">
            <span className="w-2.5 h-2.5 rounded-full bg-rose-400" />
            <span className="w-2.5 h-2.5 rounded-full bg-amber-400" />
            <span className="w-2.5 h-2.5 rounded-full bg-emerald-400" />
            <h1 className="ml-2 text-xs font-semibold text-slate-800">
              AgentSpur · 原生 AppKit 极简源码
            </h1>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleCopySwift}
              className="inline-flex items-center gap-1 rounded-xl border border-slate-200/80 bg-white/80 px-2.5 py-1 text-xs font-medium text-slate-600 shadow-[0_1px_2px_rgba(15,23,42,0.03)] hover:bg-white hover:text-slate-900 hover:border-slate-300/80 transition-all duration-150 whitespace-nowrap shrink-0 cursor-pointer"
            >
              {copiedSwift ? (
                <>
                  <Check className="w-3.5 h-3.5 text-sky-600" />
                  <span>已复制</span>
                </>
              ) : (
                <>
                  <Copy className="w-3.5 h-3.5" />
                  <span>复制</span>
                </>
              )}
            </button>
            <button
              type="button"
              onClick={handleDownloadSwiftProject}
              className="inline-flex items-center gap-1.5 rounded-xl border border-sky-300/60 bg-sky-500/[0.09] px-3 py-1 text-xs font-medium text-sky-700 shadow-[0_1px_2px_rgba(14,165,233,0.06)] hover:bg-sky-500/[0.15] hover:border-sky-400/60 transition-all duration-150 whitespace-nowrap shrink-0 cursor-pointer"
            >
              <Download className="w-3.5 h-3.5" />
              <span>下载 {swiftFileTab === 'main' ? 'main.swift' : 'Package.swift'}</span>
            </button>
          </div>
        </div>

        <div className="p-6 space-y-5">
          <div className="flex flex-wrap items-center justify-between gap-4 text-xs text-slate-500">
            <div className="flex flex-wrap items-center gap-2">
              <span className="font-medium text-slate-800">纯 AppKit 原生</span>
              <span aria-hidden="true">·</span>
              <span>无 WebView</span>
              <span aria-hidden="true">·</span>
              <span>零常驻后台进程</span>
              <span aria-hidden="true">·</span>
              <span>opencode.db SQLite WAL 只读解析</span>
            </div>

            <div className="inline-flex rounded-xl border border-slate-200/70 bg-slate-100/70 p-0.5 font-mono">
              <button
                type="button"
                onClick={() => setSwiftFileTab('main')}
                className={`rounded-[9px] px-2.5 py-0.5 text-[11px] transition-all whitespace-nowrap cursor-pointer ${
                  swiftFileTab === 'main'
                    ? 'bg-white text-sky-950 font-medium shadow-[0_1px_3px_rgba(15,23,42,0.06)] ring-1 ring-slate-900/[0.04]'
                    : 'text-slate-500 hover:text-slate-800'
                }`}
              >
                main.swift
              </button>
              <button
                type="button"
                onClick={() => setSwiftFileTab('package')}
                className={`rounded-[9px] px-2.5 py-0.5 text-[11px] transition-all whitespace-nowrap cursor-pointer ${
                  swiftFileTab === 'package'
                    ? 'bg-white text-sky-950 font-medium shadow-[0_1px_3px_rgba(15,23,42,0.06)] ring-1 ring-slate-900/[0.04]'
                    : 'text-slate-500 hover:text-slate-800'
                }`}
              >
                Package.swift
              </button>
            </div>
          </div>

          <pre className="max-h-[450px] overflow-auto rounded-xl bg-slate-900/[0.03] p-5 text-xs font-mono leading-relaxed text-slate-800">
            <code>
              {swiftFileTab === 'main'
                ? NATIVE_SWIFT_APPKIT_CODE
                : NATIVE_SWIFT_PACKAGE_CODE}
            </code>
          </pre>
        </div>
      </motion.div>
    );
  }

  // Default: Featherlight opencode TUI / iTerm2 Window + Fluid 5-State Dock
  return (
    <motion.div
      key="workspace"
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.18, ease: [0.16, 1, 0.3, 1] }}
      className="flex-1 min-w-0 rounded-2xl border border-black/[0.06] bg-white/82 backdrop-blur-3xl shadow-[0_24px_60px_-15px_rgba(15,23,42,0.08)] overflow-hidden text-slate-900"
    >
      {/* Minimalist Window Bar + iTerm2 Tabs */}
      <div className="flex flex-wrap items-center justify-between gap-4 px-5 py-3 border-b border-black/[0.05]">
        <div className="flex items-center gap-2 min-w-0">
          <span className="w-2.5 h-2.5 rounded-full bg-rose-400 shrink-0" />
          <span className="w-2.5 h-2.5 rounded-full bg-amber-400 shrink-0" />
          <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 shrink-0" />
          <span className="ml-2 text-xs font-semibold text-slate-800 truncate">
            {activeTargetRef}
          </span>
        </div>

        {/* Minimalist iTerm2 Tab Switcher */}
        <div className="flex items-center gap-0.5 rounded-xl border border-slate-200/70 bg-slate-100/70 p-0.5 font-mono text-[11px]">
          {ITERM_TABS.map((t) => {
            const isTabActive = activeItermIndex === t.index;
            return (
              <button
                key={t.index}
                type="button"
                onClick={() => {
                  for (const s of sessions) {
                    if (s.itermTabIndex === t.index) {
                      onSelectSessionFromDesktop(s.id);
                      return;
                    }
                    const sub = s.subTasks.find(
                      (st) => st.itermTabIndex === t.index
                    );
                    if (sub) {
                      onSelectSessionFromDesktop(s.id, sub.id);
                      return;
                    }
                  }
                }}
                className={`relative rounded-[9px] px-2.5 py-1 transition-colors whitespace-nowrap shrink-0 cursor-pointer ${
                  isTabActive
                    ? 'text-sky-950 font-medium'
                    : 'text-slate-400 hover:text-slate-700'
                }`}
              >
                {isTabActive && (
                  <motion.span
                    layoutId="itermTabPill"
                    transition={{ duration: 0.16, ease: [0.16, 1, 0.3, 1] }}
                    className="absolute inset-0 rounded-[9px] bg-white shadow-[0_1px_3px_rgba(15,23,42,0.06)] ring-1 ring-slate-900/[0.04]"
                  />
                )}
                <span className="relative z-10">⌘{t.index + 1}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Airy opencode TUI Read-Only View */}
      <div className="p-7 space-y-6">
        <div className="flex items-start justify-between gap-4">
          <div className="space-y-1.5 min-w-0">
            <div className="flex flex-wrap items-center gap-2 text-xs text-slate-400">
              <span>
                {selectedSubTask
                  ? `子任务 ${selectedSubTask.subagentRole}`
                  : 'Master 会话'}
              </span>
              <span aria-hidden="true">·</span>
              <span
                className={`font-mono tabular-nums font-medium ${STATUS_META[activeStatus].textClass}`}
              >
                {formatLiveStateTimerLabel(
                  activeStatus,
                  activeStateEnteredAt,
                  nowMs
                )}
              </span>
              <span aria-hidden="true">·</span>
              <span className="font-mono text-slate-500">
                {selectedSession.modelName.replace('deepseek/', '')}
              </span>
              {isSelectedSubTaskAutoFocused && (
                <>
                  <span aria-hidden="true">·</span>
                  <span className="text-sky-600 font-medium">
                    自动聚焦高亮
                  </span>
                </>
              )}
              {lastJumpNotice && (
                <>
                  <span aria-hidden="true">·</span>
                  <AnimatePresence mode="wait">
                    <motion.span
                      key={lastJumpNotice}
                      initial={{ opacity: 0, y: 2 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0 }}
                      className="text-sky-600 font-medium"
                    >
                      {lastJumpNotice}
                    </motion.span>
                  </AnimatePresence>
                </>
              )}
            </div>

            <h2 className="text-lg font-semibold tracking-tight text-slate-900 text-balance">
              {selectedSubTask ? selectedSubTask.title : selectedSession.title}
            </h2>

            <p className="text-xs text-slate-500">{selectedSession.summary}</p>
          </div>

          <AgentSpriteCanvas
            status={activeStatus}
            pack={activePack}
            size={32}
          />
        </div>

        {/* Clean Minimalist opencode TUI Stream */}
        <div
          className={`rounded-xl p-5 font-mono text-xs leading-relaxed text-slate-700 space-y-1.5 transition-colors duration-150 ${
            isSelectedSubTaskAutoFocused
              ? 'animate-focus-border bg-sky-500/[0.06]'
              : 'border border-transparent bg-slate-900/[0.028]'
          }`}
        >
          {activeLogLines.map((line, i) => (
            <div key={i} className="break-all min-h-[1rem]">
              {line}
            </div>
          ))}
          <div className="pt-3 mt-3 border-t border-black/[0.05] flex flex-wrap items-center justify-between gap-2 text-[11px] text-slate-400">
            <span className="truncate">
              {selectedSession.localPath} · {activeDbRecordRef}
            </span>
            <span className="whitespace-nowrap">
              SQLITE_OPEN_READONLY · WAL
            </span>
          </div>
        </div>

        {/* Fluid Minimalist 5-State Trigger Bar */}
        <div className="pt-2 flex flex-wrap items-center justify-between gap-3">
          <span className="text-xs text-slate-400">
            切换状态将同步重置当前状态计时器并更新右上角 15 FPS 动画
          </span>

          <div className="inline-flex flex-wrap items-center gap-0.5 rounded-xl border border-slate-200/70 bg-slate-100/70 p-0.5">
            {(Object.values(AgentStatus) as AgentStatus[]).map((st) => {
              const meta = STATUS_META[st];
              const isCurr = activeStatus === st;
              return (
                <button
                  key={st}
                  type="button"
                  onClick={() =>
                    onUpdateSessionStatus(
                      selectedSession.id,
                      st,
                      selectedSubTask?.id
                    )
                  }
                  className={`relative inline-flex items-center gap-1.5 rounded-[9px] px-2.5 py-1 text-xs font-medium transition-colors whitespace-nowrap shrink-0 cursor-pointer ${
                    isCurr
                      ? 'text-sky-950'
                      : 'text-slate-500 hover:text-slate-800'
                  }`}
                >
                  {isCurr && (
                    <motion.span
                      layoutId="fluidStatePill"
                      transition={{ duration: 0.16, ease: [0.16, 1, 0.3, 1] }}
                      className="absolute inset-0 rounded-[9px] bg-white shadow-[0_1px_3px_rgba(15,23,42,0.06)] ring-1 ring-slate-900/[0.04]"
                    />
                  )}
                  <span className="relative z-10 flex items-center gap-1.5">
                    <AgentSpriteCanvas status={st} pack={activePack} size={14} />
                    <span>{meta.label}</span>
                  </span>
                </button>
              );
            })}
          </div>
        </div>
      </div>
    </motion.div>
  );
};
