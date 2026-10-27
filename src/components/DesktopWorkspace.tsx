import React, { useEffect, useRef, useState } from 'react';
import {
  Check,
  Copy,
  Download,
  FolderOpen,
  Play,
  RotateCcw,
  SquareTerminal,
  Terminal,
} from 'lucide-react';
import {
  AgentStatus,
  CharacterPack,
  MasterSession,
  SubAgentTask,
  TargetApp,
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
  onSelectSessionFromDesktop: (sessionId: string, subTaskId?: string) => void;
}

const ITERM_TABS = [
  { index: 0, label: '1: opencode (main)' },
  { index: 1, label: '2: opencode (@explore)' },
  { index: 2, label: '3: opencode-tty' },
  { index: 3, label: '4: opencode-debug' },
];

export const DesktopWorkspace: React.FC<DesktopWorkspaceProps> = ({
  activeTab,
  onChangeTab,
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
  onSelectSessionFromDesktop,
}) => {
  const [inspectedState, setInspectedState] = useState<AgentStatus>(
    AgentStatus.Working
  );
  const [liveFrameIdx, setLiveFrameIdx] = useState<number>(0);
  const [copiedSwift, setCopiedSwift] = useState<boolean>(false);
  const [swiftFileTab, setSwiftFileTab] = useState<'main' | 'package'>('main');

  const [customName, setCustomName] = useState<string>('晴昼机械鸮');
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

  const activeTargetApp = selectedSubTask
    ? selectedSubTask.targetApp
    : selectedSession.targetApp;
  const activeTargetRef = selectedSubTask
    ? selectedSubTask.targetRef
    : selectedSession.targetRef;
  const activeStatus = selectedSubTask
    ? selectedSubTask.status
    : selectedSession.status;
  const activeLogLines = selectedSubTask
    ? selectedSubTask.logLines
    : selectedSession.logLines;
  const activeItermIndex =
    (selectedSubTask ? selectedSubTask.itermTabIndex : selectedSession.itermTabIndex) ??
    0;

  const handleDownloadSampleJson = () => {
    const payload = JSON.stringify(SAMPLE_CUSTOM_PACK_JSON, null, 2);
    const blob = new Blob([payload], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'deepseek-day-owl.rolepack.json';
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
      window.setTimeout(() => setCopiedSwift(false), 1800);
    } catch {
      // Clipboard fallback ignored cleanly
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
      author: 'Local Mac Import',
      version: '1.0.0',
      deepseekModel: customModel,
      roleDescription: '通过本地点阵编辑器生成的 DeepSeek 自定义 15 FPS 角色包。',
      archetype: 'custom_pixel',
      primaryColor: '#0369A1',
      secondaryColor: '#D97706',
      customBaseSprite: customGrid,
    };
    onImportPackObject(newPack);
  };

  if (activeTab === 'character_lab') {
    return (
      <div className="flex-1 min-w-0 rounded-xl border border-slate-200/90 bg-white/94 backdrop-blur-2xl shadow-[0_16px_40px_rgba(15,23,42,0.08)] overflow-hidden text-slate-900">
        {/* macOS Light Window Titlebar */}
        <div className="flex items-center justify-between gap-4 px-4 py-3 border-b border-slate-200/80 bg-slate-50/90">
          <div className="flex items-center gap-2">
            <span className="w-3 h-3 rounded-full bg-rose-500" />
            <span className="w-3 h-3 rounded-full bg-amber-400" />
            <span className="w-3 h-3 rounded-full bg-emerald-500" />
            <h1 className="ml-2 text-sm font-semibold text-slate-900">
              15 FPS 五状态原生帧序列与 DeepSeek 角色包
            </h1>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleDownloadSampleJson}
              className="inline-flex items-center gap-1.5 rounded-md border border-slate-300 bg-white px-2.5 py-1 text-xs font-medium text-slate-700 hover:bg-slate-100 transition-colors whitespace-nowrap shrink-0"
            >
              <Download className="w-3.5 h-3.5 shrink-0" />
              <span>下载模板 JSON</span>
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
              className="inline-flex items-center gap-1.5 rounded-md bg-sky-600 px-3 py-1 text-xs font-semibold text-white hover:bg-sky-700 transition-colors whitespace-nowrap shrink-0"
            >
              <FolderOpen className="w-3.5 h-3.5 shrink-0" />
              <span>导入角色包 (.json)</span>
            </button>
          </div>
        </div>

        <div className="p-6 space-y-8">
          {/* 1. Five Real-time States Simultaneous 15 FPS Showcase */}
          <section className="space-y-3">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <h2 className="text-base font-semibold text-slate-900">
                01. 五套完整状态动画（菜单栏 15 FPS 同步播放）
              </h2>
              <p className="text-xs text-slate-500 font-mono tabular-nums">
                当前角色：{activePack.name} · 帧周期 66.7ms · 帧序号{' '}
                {String(liveFrameIdx + 1).padStart(2, '0')}/15
              </p>
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
              {(Object.values(AgentStatus) as AgentStatus[]).map((st) => {
                const meta = STATUS_META[st];
                const isSelected = inspectedState === st;
                return (
                  <button
                    key={st}
                    type="button"
                    onClick={() => setInspectedState(st)}
                    className={`flex flex-col items-center justify-center rounded-lg border p-4 text-center transition-colors duration-150 ${
                      isSelected
                        ? 'border-sky-500 bg-sky-50/80'
                        : 'border-slate-200 bg-slate-50/50 hover:bg-slate-100/70'
                    }`}
                  >
                    <AgentSpriteCanvas status={st} pack={activePack} size={36} />
                    <span className={`mt-2.5 text-xs font-semibold ${meta.textClass}`}>
                      {meta.label}
                    </span>
                    <span className="mt-0.5 text-[11px] text-slate-500">
                      {meta.shortVerb}
                    </span>
                  </button>
                );
              })}
            </div>
          </section>

          {/* 2. 15-Frame Native Sprite Sheet Inspector */}
          <section className="space-y-3 pt-2 border-t border-slate-200">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <h2 className="text-base font-semibold text-slate-900">
                02. 逐帧分解视图：{STATUS_META[inspectedState].label}（共 15 帧 / 秒）
              </h2>
              <span className="text-xs text-slate-500">
                {STATUS_META[inspectedState].frameNote}
              </span>
            </div>

            <div className="grid grid-cols-5 sm:grid-cols-15 gap-1.5">
              {Array.from({ length: 15 }, (_, idx) => {
                const isCurrentTick = liveFrameIdx === idx;
                return (
                  <div
                    key={idx}
                    className={`flex flex-col items-center justify-center rounded-md border py-2 px-1 transition-colors duration-75 ${
                      isCurrentTick
                        ? 'border-sky-500 bg-sky-50'
                        : 'border-slate-200 bg-slate-50/70'
                    }`}
                  >
                    <AgentSpriteCanvas
                      status={inspectedState}
                      pack={activePack}
                      size={24}
                      fixedFrame={idx}
                    />
                    <span className="mt-1.5 font-mono text-[10px] tabular-nums text-slate-500">
                      F{String(idx + 1).padStart(2, '0')}
                    </span>
                  </div>
                );
              })}
            </div>
          </section>

          {/* 3. Installed Character Packs + Custom DeepSeek Pixel Role Editor */}
          <section className="grid grid-cols-1 xl:grid-cols-12 gap-6 pt-2 border-t border-slate-200 items-start">
            <div className="xl:col-span-6 space-y-3">
              <h2 className="text-base font-semibold text-slate-900">
                03. 已加载角色包列表
              </h2>
              <div className="space-y-2">
                {packs.map((pack) => {
                  const active = pack.id === activePack.id;
                  return (
                    <button
                      key={pack.id}
                      type="button"
                      onClick={() => onSelectPack(pack.id)}
                      className={`w-full text-left rounded-lg border p-3 flex items-center gap-3.5 transition-colors duration-150 ${
                        active
                          ? 'border-sky-500 bg-sky-50/80'
                          : 'border-slate-200 bg-white hover:bg-slate-50'
                      }`}
                    >
                      <AgentSpriteCanvas
                        status={inspectedState}
                        pack={pack}
                        size={28}
                      />
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center justify-between gap-2">
                          <span className="text-xs font-semibold text-slate-900 truncate">
                            {pack.name}
                          </span>
                          <span className="font-mono text-[11px] text-slate-500 shrink-0">
                            {pack.deepseekModel}
                          </span>
                        </div>
                        <p className="mt-0.5 text-[11px] text-slate-500 line-clamp-1">
                          {pack.roleDescription}
                        </p>
                      </div>
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Right half: Quick Custom DeepSeek Role Pack Creator */}
            <div className="xl:col-span-6 space-y-3">
              <div className="flex items-center justify-between gap-2">
                <h2 className="text-base font-semibold text-slate-900">
                  04. 自制 DeepSeek 角色包（点击格子绘制）
                </h2>
                <button
                  type="button"
                  onClick={() =>
                    setCustomGrid(SAMPLE_CUSTOM_PACK_JSON.customBaseSprite)
                  }
                  className="inline-flex items-center gap-1 text-xs text-slate-500 hover:text-slate-900 transition-colors whitespace-nowrap shrink-0"
                >
                  <RotateCcw className="w-3 h-3" />
                  <span>重置画布</span>
                </button>
              </div>

              <div className="flex flex-col sm:flex-row gap-4 items-start">
                <div className="grid grid-cols-12 gap-0.5 p-2 rounded-lg border border-slate-200 bg-slate-100/80 shrink-0">
                  {customGrid.map((row, rIdx) =>
                    row.split('').map((cell, cIdx) => (
                      <button
                        key={`${rIdx}-${cIdx}`}
                        type="button"
                        onClick={() => toggleGridCell(rIdx, cIdx)}
                        aria-label={`像素格 ${rIdx + 1},${cIdx + 1}`}
                        className={`w-4 h-4 rounded-[2px] transition-colors ${
                          cell === '#'
                            ? 'bg-sky-700'
                            : cell === '+'
                            ? 'bg-amber-500'
                            : 'bg-white hover:bg-slate-200'
                        }`}
                      />
                    ))
                  )}
                </div>

                <div className="flex-1 space-y-3 w-full">
                  <div>
                    <label
                      htmlFor="custom-pack-name"
                      className="block text-xs font-medium text-slate-600 mb-1"
                    >
                      角色名称
                    </label>
                    <input
                      id="custom-pack-name"
                      type="text"
                      value={customName}
                      onChange={(e) => setCustomName(e.target.value)}
                      className="w-full rounded-md border border-slate-300 bg-white px-2.5 py-1.5 text-xs text-slate-900 focus:outline-none focus:ring-1 focus:ring-sky-600"
                    />
                  </div>

                  <div>
                    <label
                      htmlFor="custom-pack-model"
                      className="block text-xs font-medium text-slate-600 mb-1"
                    >
                      绑定 opencode DeepSeek 模型
                    </label>
                    <select
                      id="custom-pack-model"
                      value={customModel}
                      onChange={(e) => setCustomModel(e.target.value)}
                      className="w-full rounded-md border border-slate-300 bg-white px-2.5 py-1.5 text-xs text-slate-900 focus:outline-none focus:ring-1 focus:ring-sky-600"
                    >
                      <option value="deepseek/deepseek-reasoner">
                        deepseek/deepseek-reasoner
                      </option>
                      <option value="deepseek/deepseek-chat">
                        deepseek/deepseek-chat
                      </option>
                    </select>
                  </div>

                  <button
                    type="button"
                    onClick={handleApplyCustomPack}
                    className="w-full rounded-md bg-sky-600 px-3 py-2 text-xs font-semibold text-white hover:bg-sky-700 transition-colors whitespace-nowrap"
                  >
                    载入到右上角菜单栏
                  </button>
                </div>
              </div>
            </div>
          </section>
        </div>
      </div>
    );
  }

  if (activeTab === 'swift_source') {
    return (
      <div className="flex-1 min-w-0 rounded-xl border border-slate-200/90 bg-white/94 backdrop-blur-2xl shadow-[0_16px_40px_rgba(15,23,42,0.08)] overflow-hidden text-slate-900">
        <div className="flex items-center justify-between gap-4 px-4 py-3 border-b border-slate-200/80 bg-slate-50/90">
          <div className="flex items-center gap-2">
            <span className="w-3 h-3 rounded-full bg-rose-500" />
            <span className="w-3 h-3 rounded-full bg-amber-400" />
            <span className="w-3 h-3 rounded-full bg-emerald-500" />
            <h1 className="ml-2 text-sm font-semibold text-slate-900">
              原生 AppKit 极轻架构（零 WebView · 零常驻守护进程）
            </h1>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleCopySwift}
              className="inline-flex items-center gap-1.5 rounded-md border border-slate-300 bg-white px-2.5 py-1 text-xs font-medium text-slate-700 hover:bg-slate-100 transition-colors whitespace-nowrap shrink-0"
            >
              {copiedSwift ? (
                <>
                  <Check className="w-3.5 h-3.5 text-emerald-600" />
                  <span>已复制源码</span>
                </>
              ) : (
                <>
                  <Copy className="w-3.5 h-3.5" />
                  <span>复制代码</span>
                </>
              )}
            </button>
            <button
              type="button"
              onClick={handleDownloadSwiftProject}
              className="inline-flex items-center gap-1.5 rounded-md bg-sky-600 px-3 py-1 text-xs font-semibold text-white hover:bg-sky-700 transition-colors whitespace-nowrap shrink-0"
            >
              <Download className="w-3.5 h-3.5" />
              <span>下载 {swiftFileTab === 'main' ? 'main.swift' : 'Package.swift'}</span>
            </button>
          </div>
        </div>

        <div className="p-6 space-y-6">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 pb-5 border-b border-slate-200">
            <div>
              <div className="text-xs text-slate-500">视图渲染层</div>
              <div className="mt-1 text-sm font-semibold text-slate-900">
                纯 AppKit NSStatusItem + NSMenu
              </div>
              <p className="mt-1 text-xs text-slate-600">
                不链接 WebKit.framework，内存常驻约 11 MB，预烘焙 75 张 Retina 位图以 15 FPS 切换。
              </p>
            </div>
            <div>
              <div className="text-xs text-slate-500">会话读取方式</div>
              <div className="mt-1 text-sm font-semibold text-slate-900">
                本机只读 FSEvents 按需唤醒
              </div>
              <p className="mt-1 text-xs text-slate-600">
                无后台轮询守护进程；仅在 ~/.local/share/opencode/storage 文件写入时以 O_RDONLY 读取。
              </p>
            </div>
            <div>
              <div className="text-xs text-slate-500">终端跳转与静音提醒</div>
              <div className="mt-1 text-sm font-semibold text-slate-900">
                iTerm2 TTY 定位 + UNNotification
              </div>
              <p className="mt-1 text-xs text-slate-600">
                点一下跳回对应 opencode TUI 窗口或指定 iTerm2 标签页，完成提醒严格静音且可关闭。
              </p>
            </div>
          </div>

          <div className="space-y-3">
            <div className="flex items-center justify-between gap-4">
              <div className="inline-flex rounded-lg bg-slate-200/75 p-0.5">
                <button
                  type="button"
                  onClick={() => setSwiftFileTab('main')}
                  className={`rounded-md px-3 py-1 text-xs font-mono transition-colors whitespace-nowrap ${
                    swiftFileTab === 'main'
                      ? 'bg-white text-slate-900 shadow-xs'
                      : 'text-slate-600 hover:text-slate-900'
                  }`}
                >
                  Sources/AgentBar/main.swift
                </button>
                <button
                  type="button"
                  onClick={() => setSwiftFileTab('package')}
                  className={`rounded-md px-3 py-1 text-xs font-mono transition-colors whitespace-nowrap ${
                    swiftFileTab === 'package'
                      ? 'bg-white text-slate-900 shadow-xs'
                      : 'text-slate-600 hover:text-slate-900'
                  }`}
                >
                  Package.swift
                </button>
              </div>

              <span className="text-xs font-mono text-slate-500">
                编译命令：swift build -c release
              </span>
            </div>

            <pre className="max-h-[430px] overflow-auto rounded-lg border border-slate-200 bg-slate-50 p-4 text-xs font-mono leading-relaxed text-slate-800">
              <code>
                {swiftFileTab === 'main'
                  ? NATIVE_SWIFT_APPKIT_CODE
                  : NATIVE_SWIFT_PACKAGE_CODE}
              </code>
            </pre>
          </div>
        </div>
      </div>
    );
  }

  // Default: 'workspace' — Simulated opencode TUI / iTerm2 Light Terminal Window Linked to Menu Bar Clicks
  return (
    <div className="flex-1 min-w-0 flex flex-col gap-5">
      <div className="rounded-xl border border-slate-200/90 bg-white/94 backdrop-blur-2xl shadow-[0_16px_40px_rgba(15,23,42,0.08)] overflow-hidden text-slate-900">
        {/* macOS Light Traffic Lights + Target App Header */}
        <div className="flex flex-wrap items-center justify-between gap-3 px-4 py-3 border-b border-slate-200/80 bg-slate-50/90">
          <div className="flex items-center gap-2 min-w-0">
            <span className="w-3 h-3 rounded-full bg-rose-500 shrink-0" />
            <span className="w-3 h-3 rounded-full bg-amber-400 shrink-0" />
            <span className="w-3 h-3 rounded-full bg-emerald-500 shrink-0" />
            <div className="ml-2 flex items-center gap-2 min-w-0">
              {activeTargetApp === TargetApp.OpenCodeTUI ? (
                <SquareTerminal className="w-4 h-4 text-sky-600 shrink-0" />
              ) : (
                <Terminal className="w-4 h-4 text-emerald-600 shrink-0" />
              )}
              <span className="text-sm font-semibold text-slate-900 truncate">
                {activeTargetRef}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-2 text-xs text-slate-500 font-mono">
            {lastJumpNotice ? (
              <span className="text-sky-700 font-medium">{lastJumpNotice}</span>
            ) : (
              <span className="truncate max-w-xs">{selectedSession.localPath}</span>
            )}
          </div>
        </div>

        {/* Authentic Light-Mode iTerm2 Tab Bar Running opencode TUI */}
        <div className="grid grid-cols-2 sm:grid-cols-4 border-b border-slate-200 bg-slate-100/85 text-xs font-mono">
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
                className={`px-3 py-2 text-left truncate border-r border-slate-200/80 transition-colors ${
                  isTabActive
                    ? 'bg-white text-slate-900 font-semibold'
                    : 'text-slate-500 hover:text-slate-800 hover:bg-white/60'
                }`}
              >
                ⌘{t.index + 1} · {t.label}
              </button>
            );
          })}
        </div>

        {/* Active opencode TUI Session / Sub-Agent Read-Only Local Snapshot View */}
        <div className="p-6 space-y-5">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div className="space-y-1 min-w-0 flex-1">
              <div className="flex items-center gap-2 text-xs text-slate-500">
                <span>
                  {selectedSubTask
                    ? `opencode 子任务 (${selectedSubTask.subagentRole})`
                    : 'opencode Master 主会话'}
                </span>
                <span aria-hidden="true">·</span>
                <span className="font-mono text-slate-700">
                  {selectedSession.modelName}
                </span>
                <span aria-hidden="true">·</span>
                <span>本机文件只读映射</span>
              </div>

              <h2 className="text-lg font-semibold text-slate-900 text-balance">
                {selectedSubTask ? selectedSubTask.title : selectedSession.title}
              </h2>

              <p className="text-sm text-slate-600">{selectedSession.summary}</p>
            </div>

            <div className="flex items-center gap-2.5 rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 shrink-0">
              <AgentSpriteCanvas
                status={activeStatus}
                pack={activePack}
                size={24}
              />
              <div className="text-xs">
                <div className={`font-semibold ${STATUS_META[activeStatus].textClass}`}>
                  {STATUS_META[activeStatus].label}
                </div>
                <div className="text-[11px] text-slate-500 font-mono">15 FPS 播放中</div>
              </div>
            </div>
          </div>

          {/* Light-Theme opencode TUI Terminal Box */}
          <div className="rounded-lg border border-slate-200 bg-slate-50/90 p-4 font-mono text-xs leading-relaxed text-slate-800 space-y-1.5">
            <div className="pb-2 mb-2 border-b border-slate-200/80 flex items-center justify-between text-[11px] text-slate-500">
              <span>opencode storage：{selectedSession.localPath}</span>
              <span>
                {selectedSubTask ? selectedSubTask.localOffset : selectedSession.updatedAt}
              </span>
            </div>
            {activeLogLines.map((line, i) => (
              <div key={i} className="break-all">
                {line}
              </div>
            ))}
            <div className="pt-2 mt-2 border-t border-slate-200/70 flex items-center justify-between text-[11px] text-slate-400">
              <span>tab switch agent · ctrl+p commands · ctrl+c interrupt</span>
              <span>opencode TUI (Light)</span>
            </div>
          </div>

          {/* Interactive Simulation Bar: Test All 5 Real-time Menu Bar States & Silent Completion Toast */}
          <div className="pt-3 border-t border-slate-200 flex flex-wrap items-center justify-between gap-3">
            <div className="space-y-0.5">
              <div className="text-xs font-semibold text-slate-800">
                状态演练台（模拟 opencode 本机状态变更，观察右上角菜单栏 15 FPS 动画）
              </div>
              <div className="text-[11px] text-slate-500">
                状态栏本身保持纯净只读；点击下方状态可测试菜单栏动画或触发「完成」静音横幅
              </div>
            </div>

            <div className="flex flex-wrap items-center gap-1.5">
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
                    className={`inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1.5 text-xs font-medium transition-colors duration-150 whitespace-nowrap shrink-0 ${
                      isCurr
                        ? 'border-sky-500 bg-sky-50 text-sky-900 font-semibold'
                        : 'border-slate-200 bg-white text-slate-700 hover:bg-slate-100 hover:text-slate-900'
                    }`}
                  >
                    <AgentSpriteCanvas status={st} pack={activePack} size={14} />
                    <span>{meta.label}</span>
                  </button>
                );
              })}
            </div>
          </div>
        </div>
      </div>

      {/* Bottom Quick Strip */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <button
          type="button"
          onClick={() => onChangeTab('character_lab')}
          className="group text-left rounded-xl border border-slate-200/90 bg-white/88 p-4 backdrop-blur-xl hover:bg-white shadow-xs transition-colors flex items-center justify-between gap-4"
        >
          <div className="space-y-1 min-w-0">
            <div className="text-xs font-semibold text-slate-900 group-hover:text-sky-700 transition-colors">
              查看五状态 × 15 帧分解与 DeepSeek 角色包工坊
            </div>
            <p className="text-xs text-slate-500 truncate">
              当前角色：{activePack.name} · 支持绘制点阵或导入本地 .json 角色包
            </p>
          </div>
          <Play className="w-4 h-4 text-slate-400 group-hover:text-sky-600 shrink-0" />
        </button>

        <button
          type="button"
          onClick={() => onChangeTab('swift_source')}
          className="group text-left rounded-xl border border-slate-200/90 bg-white/88 p-4 backdrop-blur-xl hover:bg-white shadow-xs transition-colors flex items-center justify-between gap-4"
        >
          <div className="space-y-1 min-w-0">
            <div className="text-xs font-semibold text-slate-900 group-hover:text-sky-700 transition-colors">
              获取 macOS 原生 AppKit Swift 工程代码
            </div>
            <p className="text-xs text-slate-500 truncate">
              无 WebView · 无常驻后台进程 · 只读监听 ~/.local/share/opencode
            </p>
          </div>
          <Download className="w-4 h-4 text-slate-400 group-hover:text-sky-600 shrink-0" />
        </button>
      </div>
    </div>
  );
};
