import React, { useCallback, useEffect, useMemo, useState } from 'react';
import wallpaperUrl from './assets/images/macos_light_daylight_wallpaper_1793088180493.jpg';
import {
  AgentStatus,
  CharacterPack,
  MasterSession,
  QuotaState,
  SilentToastItem,
} from './types/agent';
import {
  BUILTIN_CHARACTER_PACKS,
  INITIAL_QUOTA,
  INITIAL_SESSIONS,
} from './data/initialData';
import { DesktopTabMode, MacMenuBar } from './components/MacMenuBar';
import { StatusPopover } from './components/StatusPopover';
import { DesktopWorkspace } from './components/DesktopWorkspace';
import { SilentNotificationBanner } from './components/SilentNotificationBanner';

const STORAGE_PACKS_KEY = 'agentbar_custom_packs_light_v2';
const STORAGE_ACTIVE_PACK_KEY = 'agentbar_active_pack_id_v2';
const STORAGE_SILENT_ALERT_KEY = 'agentbar_silent_alert_v2';

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
    if (activeDesktopTab === 'character_lab') return 'AgentBar · 角色包预览';
    if (activeDesktopTab === 'swift_source') return 'Xcode · AgentBar';
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
    const ss = String(now.getSeconds()).padStart(2, '0');

    window.setTimeout(() => {
      setQuota((prev) => ({
        ...prev,
        remainingUsd: Math.max(
          0.5,
          Number((prev.remainingUsd - 0.02).toFixed(2))
        ),
        lastRefreshedAt: `${hh}:${mm}:${ss}`,
      }));
      setIsRefreshingQuota(false);
    }, 220);
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
    setImportFeedback(`已载入 DeepSeek 角色包：${newPack.name}`);
    window.setTimeout(() => setImportFeedback(null), 3200);
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
              typeof parsed.author === 'string' ? parsed.author : 'Local User',
            version:
              typeof parsed.version === 'string' ? parsed.version : '1.0.0',
            deepseekModel:
              typeof parsed.deepseekModel === 'string'
                ? parsed.deepseekModel
                : 'deepseek/deepseek-reasoner',
            roleDescription:
              typeof parsed.roleDescription === 'string'
                ? parsed.roleDescription
                : '从本地 JSON 导入的自定义 DeepSeek 角色包。',
            archetype:
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
                : '#0369A1',
            secondaryColor:
              typeof parsed.secondaryColor === 'string'
                ? parsed.secondaryColor
                : '#D97706',
            customBaseSprite: Array.isArray(parsed.customBaseSprite)
              ? parsed.customBaseSprite
              : undefined,
          };
          handleImportPackObject(importedPack);
        } catch {
          setImportFeedback('角色包 JSON 格式解析失败，请检查字段结构');
          window.setTimeout(() => setImportFeedback(null), 3500);
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
      setLastJumpNotice(`已唤起并定位至 ${destLabel}`);
      window.setTimeout(() => setLastJumpNotice(null), 2600);
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
      }, 5500);
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
                st.id === subTaskId ? { ...st, status: nextStatus } : st
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
          };
        })
      );
    },
    [pushSilentCompletionToast]
  );

  const handleDismissToast = useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  return (
    <div
      id="top"
      className="relative min-h-screen w-full bg-slate-100 text-slate-900 flex flex-col"
    >
      {/* Bright Airy macOS Sequoia Daylight Wallpaper + Soft Light Scrim */}
      <div className="fixed inset-0 z-0 pointer-events-none overflow-hidden bg-gradient-to-br from-sky-50 via-white to-slate-100">
        {!wallpaperFailed && (
          <img
            src={wallpaperUrl}
            alt="macOS Sequoia 明亮浅色桌面背景"
            referrerPolicy="no-referrer"
            onError={() => setWallpaperFailed(true)}
            className="h-full w-full object-cover opacity-85"
          />
        )}
        <div className="absolute inset-0 bg-gradient-to-b from-white/40 via-white/25 to-slate-100/55" />
      </div>

      {/* Pinned Top macOS Light Menu Bar */}
      <MacMenuBar
        activeStatus={derivedMenuBarStatus}
        activePack={activePack}
        quota={quota}
        isPopoverOpen={isPopoverOpen}
        onTogglePopover={() => setIsPopoverOpen((v) => !v)}
        isRefreshingQuota={isRefreshingQuota}
        activeDesktopTab={activeDesktopTab}
        onSelectDesktopTab={setActiveDesktopTab}
        focusedAppLabel={focusedAppLabel}
      />

      {/* Silent Completion Notification Banner */}
      <SilentNotificationBanner
        toasts={toasts}
        activePack={activePack}
        onJump={handleJumpToSession}
        onDismiss={handleDismissToast}
      />

      {/* Import Feedback Banner */}
      {importFeedback && (
        <div className="fixed bottom-5 right-5 z-50 rounded-lg border border-slate-200 bg-white/95 px-4 py-2.5 text-xs font-medium text-slate-800 shadow-lg backdrop-blur-xl">
          {importFeedback}
        </div>
      )}

      {/* Main 1440px Bright macOS Desktop Viewport */}
      <main className="relative z-10 mx-auto flex w-full max-w-[1440px] flex-1 flex-col-reverse lg:flex-row items-start gap-6 px-5 py-5">
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
      </main>
    </div>
  );
}
