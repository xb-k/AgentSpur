import React, { useCallback, useEffect, useMemo, useState } from 'react';
import wallpaperUrl from './assets/images/macos_light_daylight_wallpaper_1793088180493.jpg';
import {
  AgentStatus,
  CharacterPack,
  MasterSession,
  QuotaState,
  SilentToastItem,
  SubAgentTask,
} from './types/agent';
import {
  BUILTIN_CHARACTER_PACKS,
  INITIAL_QUOTA,
  INITIAL_SESSIONS,
  INITIAL_WEEKLY_EFFICIENCY,
} from './data/initialData';
import { DesktopTabMode, MacMenuBar } from './components/MacMenuBar';
import { StatusPopover } from './components/StatusPopover';
import { DesktopWorkspace } from './components/DesktopWorkspace';
import { SilentNotificationBanner } from './components/SilentNotificationBanner';
import { WeeklyEfficiencyChart } from './components/WeeklyEfficiencyChart';

const STORAGE_PACKS_KEY = 'agentbar_custom_packs_gin_v3';
const STORAGE_ACTIVE_PACK_KEY = 'agentbar_active_pack_gin_v3';
const STORAGE_SILENT_ALERT_KEY = 'agentbar_silent_alert_gin_v3';

export default function App() {
  const [sessions, setSessions] = useState<MasterSession[]>(INITIAL_SESSIONS);
  const [quota, setQuota] = useState<QuotaState>(INITIAL_QUOTA);
  const [isRefreshingQuota, setIsRefreshingQuota] = useState<boolean>(false);
  const [isPopoverOpen, setIsPopoverOpen] = useState<boolean>(true);
  const [activeDesktopTab, setActiveDesktopTab] =
    useState<DesktopTabMode>('workspace');

  const [selectedSessionId, setSelectedSessionId] = useState<string>(
    INITIAL_SESSIONS[0].id
  );
  const [selectedSubTaskId, setSelectedSubTaskId] = useState<string | undefined>(
    undefined
  );
  const [menuBarFocusStatus, setMenuBarFocusStatus] = useState<AgentStatus | null>(
    null
  );
  const [lastJumpNotice, setLastJumpNotice] = useState<string | null>(null);
  const [importFeedback, setImportFeedback] = useState<string | null>(null);
  const [wallpaperFailed, setWallpaperFailed] = useState<boolean>(false);

  const [silentAlertEnabled, setSilentAlertEnabled] = useState<boolean>(() => {
    try {
      const saved = localStorage.getItem(STORAGE_SILENT_ALERT_KEY);
      return saved === null ? true : saved === 'true';
    } catch {
      return true;
    }
  });

  const [toasts, setToasts] = useState<SilentToastItem[]>([]);

  const [customPacks, setCustomPacks] = useState<CharacterPack[]>(() => {
    try {
      const raw = localStorage.getItem(STORAGE_PACKS_KEY);
      if (!raw) return [];
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  });

  const allPacks = useMemo(
    () => [...BUILTIN_CHARACTER_PACKS, ...customPacks],
    [customPacks]
  );

  const [activePackId, setActivePackId] = useState<string>(() => {
    try {
      return (
        localStorage.getItem(STORAGE_ACTIVE_PACK_KEY) ||
        BUILTIN_CHARACTER_PACKS[0].id
      );
    } catch {
      return BUILTIN_CHARACTER_PACKS[0].id;
    }
  });

  const activePack = useMemo(
    () => allPacks.find((p) => p.id === activePackId) || BUILTIN_CHARACTER_PACKS[0],
    [allPacks, activePackId]
  );

  const derivedMenuBarStatus = useMemo<AgentStatus>(() => {
    if (menuBarFocusStatus) return menuBarFocusStatus;
    if (sessions.some((s) => s.status === AgentStatus.Confirm)) {
      return AgentStatus.Confirm;
    }
    if (sessions.some((s) => s.status === AgentStatus.Working)) {
      return AgentStatus.Working;
    }
    if (sessions.some((s) => s.status === AgentStatus.Thinking)) {
      return AgentStatus.Thinking;
    }
    if (sessions.some((s) => s.status === AgentStatus.Error)) {
      return AgentStatus.Error;
    }
    return AgentStatus.Completed;
  }, [menuBarFocusStatus, sessions]);

  const urgentSubTask = useMemo<SubAgentTask | undefined>(() => {
    const priorityMap: Record<AgentStatus, number> = {
      [AgentStatus.Confirm]: 1,
      [AgentStatus.Error]: menuBarFocusStatus === AgentStatus.Error ? 0 : 2,
      [AgentStatus.Working]: 3,
      [AgentStatus.Thinking]: 4,
      [AgentStatus.Completed]: 5,
    };
    const allSubs = sessions.flatMap((s) => s.subTasks);
    if (allSubs.length === 0) return undefined;
    return [...allSubs].sort(
      (a, b) => priorityMap[a.status] - priorityMap[b.status]
    )[0];
  }, [sessions, menuBarFocusStatus]);

  const selectedSession = useMemo(
    () => sessions.find((s) => s.id === selectedSessionId) || sessions[0],
    [sessions, selectedSessionId]
  );

  const selectedSubTask = useMemo(
    () =>
      selectedSubTaskId
        ? selectedSession.subTasks.find((st) => st.id === selectedSubTaskId)
        : undefined,
    [selectedSession, selectedSubTaskId]
  );

  const focusedAppLabel = useMemo(() => {
    if (activeDesktopTab === 'character_lab') return 'AgentSpur';
    if (activeDesktopTab === 'swift_source') return 'Xcode';
    const app = selectedSubTask
      ? selectedSubTask.targetApp
      : selectedSession.targetApp;
    return app;
  }, [activeDesktopTab, selectedSession, selectedSubTask]);

  const handleRefreshQuota = useCallback(() => {
    setIsRefreshingQuota(true);
    const now = new Date();
    const hh = String(now.getHours()).padStart(2, '0');
    const mm = String(now.getMinutes()).padStart(2, '0');

    window.setTimeout(() => {
      setQuota((prev) => ({
        ...prev,
        remainingUsd: Math.max(
          0.5,
          Number((prev.remainingUsd - 0.02).toFixed(2))
        ),
        lastRefreshedAt: `${hh}:${mm}`,
      }));
      setIsRefreshingQuota(false);
    }, 200);
  }, []);

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'r') {
        e.preventDefault();
        handleRefreshQuota();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [handleRefreshQuota]);

  const handleToggleSilentAlert = useCallback(() => {
    setSilentAlertEnabled((prev) => {
      const next = !prev;
      try {
        localStorage.setItem(STORAGE_SILENT_ALERT_KEY, String(next));
      } catch {
        // Ignore storage error
      }
      return next;
    });
  }, []);

  const handleSelectPack = useCallback((packId: string) => {
    setActivePackId(packId);
    try {
      localStorage.setItem(STORAGE_ACTIVE_PACK_KEY, packId);
    } catch {
      // Ignore storage error
    }
  }, []);

  const handleImportPackObject = useCallback((newPack: CharacterPack) => {
    setCustomPacks((prev) => {
      const filtered = prev.filter((p) => p.id !== newPack.id);
      const updated = [...filtered, newPack];
      try {
        localStorage.setItem(STORAGE_PACKS_KEY, JSON.stringify(updated));
        localStorage.setItem(STORAGE_ACTIVE_PACK_KEY, newPack.id);
      } catch {
        // Ignore storage error
      }
      return updated;
    });
    setActivePackId(newPack.id);
    setImportFeedback(`已切换角色：${newPack.name}`);
    window.setTimeout(() => setImportFeedback(null), 2600);
  }, []);

  const handleImportPackFile = useCallback(
    (file: File) => {
      const reader = new FileReader();
      reader.onload = () => {
        try {
          const parsed = JSON.parse(String(reader.result || '{}'));
          const importedPack: CharacterPack = {
            id:
              typeof parsed.id === 'string' && parsed.id.trim()
                ? parsed.id.trim()
                : `imported-${Date.now()}`,
            name:
              typeof parsed.name === 'string' && parsed.name.trim()
                ? parsed.name.trim()
                : file.name.replace(/\.json$/i, ''),
            author:
              typeof parsed.author === 'string' ? parsed.author : 'Local Mac',
            version:
              typeof parsed.version === 'string' ? parsed.version : '1.0.0',
            deepseekModel:
              typeof parsed.deepseekModel === 'string'
                ? parsed.deepseekModel
                : 'deepseek/deepseek-reasoner',
            roleDescription:
              typeof parsed.roleDescription === 'string'
                ? parsed.roleDescription
                : '从本地 JSON 导入的极简角色包。',
            archetype:
              parsed.archetype === 'droplet' ||
              parsed.archetype === 'glyph' ||
              parsed.archetype === 'whale' ||
              parsed.archetype === 'neko' ||
              parsed.archetype === 'kitsune' ||
              parsed.archetype === 'custom_pixel'
                ? parsed.archetype
                : 'custom_pixel',
            primaryColor:
              typeof parsed.primaryColor === 'string'
                ? parsed.primaryColor
                : '#0F172A',
            secondaryColor:
              typeof parsed.secondaryColor === 'string'
                ? parsed.secondaryColor
                : '#0EA5E9',
            customBaseSprite: Array.isArray(parsed.customBaseSprite)
              ? parsed.customBaseSprite
              : undefined,
          };
          handleImportPackObject(importedPack);
        } catch {
          setImportFeedback('角色包 JSON 解析失败');
          window.setTimeout(() => setImportFeedback(null), 3000);
        }
      };
      reader.readAsText(file);
    },
    [handleImportPackObject]
  );

  const handleJumpToSession = useCallback(
    (sessionId: string, subTaskId?: string) => {
      const targetSession = sessions.find((s) => s.id === sessionId);
      if (!targetSession) return;
      const targetSub = subTaskId
        ? targetSession.subTasks.find((st) => st.id === subTaskId)
        : undefined;

      setSelectedSessionId(sessionId);
      setSelectedSubTaskId(subTaskId);
      setActiveDesktopTab('workspace');

      const destLabel = targetSub ? targetSub.targetRef : targetSession.targetRef;
      const nextSt = targetSub ? targetSub.status : targetSession.status;
      setMenuBarFocusStatus(nextSt);
      setLastJumpNotice(`已跳回 ${destLabel}`);
      window.setTimeout(() => setLastJumpNotice(null), 2200);
    },
    [sessions]
  );

  const pushSilentCompletionToast = useCallback(
    (
      title: string,
      targetSession: MasterSession,
      subId?: string,
      targetRefOverride?: string
    ) => {
      if (!silentAlertEnabled) return;
      const now = new Date();
      const timeStr = `${String(now.getHours()).padStart(2, '0')}:${String(
        now.getMinutes()
      ).padStart(2, '0')}`;
      const id = `toast-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
      const item: SilentToastItem = {
        id,
        sessionTitle: title,
        targetApp: targetSession.targetApp,
        targetRef: targetRefOverride || targetSession.targetRef,
        sessionId: targetSession.id,
        subTaskId: subId,
        timestamp: timeStr,
      };
      setToasts((prev) => [item, ...prev].slice(0, 3));
      window.setTimeout(() => {
        setToasts((prev) => prev.filter((t) => t.id !== id));
      }, 5000);
    },
    [silentAlertEnabled]
  );

  const handleUpdateSessionStatus = useCallback(
    (sessionId: string, nextStatus: AgentStatus, subTaskId?: string) => {
      setMenuBarFocusStatus(nextStatus);

      setSessions((prev) =>
        prev.map((s) => {
          if (s.id !== sessionId) return s;

          if (subTaskId) {
            const targetSub = s.subTasks.find((st) => st.id === subTaskId);
            if (
              targetSub &&
              targetSub.status !== AgentStatus.Completed &&
              nextStatus === AgentStatus.Completed
            ) {
              pushSilentCompletionToast(
                targetSub.title,
                s,
                targetSub.id,
                targetSub.targetRef
              );
            }
            return {
              ...s,
              updatedAt: '刚刚',
              subTasks: s.subTasks.map((st) =>
                st.id === subTaskId
                  ? {
                      ...st,
                      status: nextStatus,
                      elapsed:
                        nextStatus === AgentStatus.Completed &&
                        st.elapsed === '待确认'
                          ? '1.6s'
                          : st.elapsed,
                    }
                  : st
              ),
            };
          }

          if (
            s.status !== AgentStatus.Completed &&
            nextStatus === AgentStatus.Completed
          ) {
            pushSilentCompletionToast(s.title, s);
          }

          return {
            ...s,
            status: nextStatus,
            updatedAt: '刚刚',
            duration:
              nextStatus === AgentStatus.Completed
                ? s.duration || '48s'
                : s.duration,
          };
        })
      );
    },
    [pushSilentCompletionToast]
  );

  const weeklyEfficiencyData = useMemo(() => {
    const extraCompleted = Math.max(
      0,
      sessions.filter((s) => s.status === AgentStatus.Completed).length - 2
    );
    return INITIAL_WEEKLY_EFFICIENCY.map((pt) =>
      pt.isToday
        ? {
            ...pt,
            completedCount: pt.completedCount + extraCompleted,
            tasksPerHour: Number(
              (pt.tasksPerHour + extraCompleted * 0.4).toFixed(1)
            ),
            avgSeconds: Math.max(24, pt.avgSeconds - extraCompleted * 2),
          }
        : pt
    );
  }, [sessions]);

  const handleDismissToast = useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  return (
    <div
      id="top"
      className="relative min-h-screen w-full bg-[#F8FAFC] text-slate-900 flex flex-col"
    >
      {/* Featherlight Sunlit Daylight Backdrop */}
      <div className="fixed inset-0 z-0 pointer-events-none overflow-hidden bg-gradient-to-br from-white via-slate-50 to-sky-50/40">
        {!wallpaperFailed && (
          <img
            src={wallpaperUrl}
            alt="macOS 明亮极简桌面背景"
            referrerPolicy="no-referrer"
            onError={() => setWallpaperFailed(true)}
            className="h-full w-full object-cover opacity-65"
          />
        )}
        <div className="absolute inset-0 bg-white/45" />
      </div>

      {/* Featherlight macOS Menu Bar */}
      <MacMenuBar
        activeStatus={derivedMenuBarStatus}
        activePack={activePack}
        quota={quota}
        urgentSubTask={urgentSubTask}
        isPopoverOpen={isPopoverOpen}
        onTogglePopover={() => setIsPopoverOpen((v) => !v)}
        isRefreshingQuota={isRefreshingQuota}
        activeDesktopTab={activeDesktopTab}
        onSelectDesktopTab={setActiveDesktopTab}
        focusedAppLabel={focusedAppLabel}
      />

      {/* Minimalist Silent Completion Notification */}
      <SilentNotificationBanner
        toasts={toasts}
        activePack={activePack}
        onJump={handleJumpToSession}
        onDismiss={handleDismissToast}
      />

      {/* Subtle Role Switch Feedback */}
      {importFeedback && (
        <div className="fixed bottom-5 right-5 z-50 rounded-full border border-black/[0.06] bg-white/90 px-3.5 py-1.5 text-xs font-medium text-slate-700 shadow-md backdrop-blur-2xl">
          {importFeedback}
        </div>
      )}

      {/* Airy Minimalist Desktop Canvas */}
      <main className="relative z-10 mx-auto flex w-full max-w-[1380px] flex-1 flex-col gap-6 px-6 py-7">
        <div className="flex w-full flex-col-reverse lg:flex-row items-start gap-7">
          <DesktopWorkspace
            activeTab={activeDesktopTab}
            onChangeTab={setActiveDesktopTab}
            sessions={sessions}
            selectedSession={selectedSession}
            selectedSubTask={selectedSubTask}
            lastJumpNotice={lastJumpNotice}
            activePack={activePack}
            packs={allPacks}
            onSelectPack={handleSelectPack}
            onImportPackObject={handleImportPackObject}
            onImportPackFile={handleImportPackFile}
            onUpdateSessionStatus={handleUpdateSessionStatus}
            onSelectSessionFromDesktop={(sId, subId) => {
              setSelectedSessionId(sId);
              setSelectedSubTaskId(subId);
            }}
          />

          <StatusPopover
            isOpen={isPopoverOpen}
            activeStatus={derivedMenuBarStatus}
            sessions={sessions}
            quota={quota}
            isRefreshingQuota={isRefreshingQuota}
            onRefreshQuota={handleRefreshQuota}
            silentAlertEnabled={silentAlertEnabled}
            onToggleSilentAlert={handleToggleSilentAlert}
            packs={allPacks}
            activePack={activePack}
            onSelectPack={handleSelectPack}
            onImportPackFile={handleImportPackFile}
            selectedSessionId={selectedSessionId}
            selectedSubTaskId={selectedSubTaskId}
            onJumpToSession={handleJumpToSession}
          />
        </div>

        {/* Bottom D3.js Weekly Task Processing Efficiency Line Chart */}
        <WeeklyEfficiencyChart data={weeklyEfficiencyData} />
      </main>
    </div>
  );
}
