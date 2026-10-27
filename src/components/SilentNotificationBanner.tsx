import React from 'react';
import { BellOff, ExternalLink, X } from 'lucide-react';
import { AgentStatus, CharacterPack, SilentToastItem } from '../types/agent';
import { AgentSpriteCanvas } from './AgentSpriteCanvas';

interface SilentNotificationBannerProps {
  toasts: SilentToastItem[];
  activePack: CharacterPack;
  onJump: (sessionId: string, subTaskId?: string) => void;
  onDismiss: (id: string) => void;
}

export const SilentNotificationBanner: React.FC<SilentNotificationBannerProps> = ({
  toasts,
  activePack,
  onJump,
  onDismiss,
}) => {
  if (toasts.length === 0) return null;

  return (
    <div
      aria-live="polite"
      className="fixed top-12 right-5 z-50 flex flex-col gap-2.5 w-84 max-w-[calc(100vw-2.5rem)] pointer-events-none"
    >
      {toasts.map((toast) => (
        <div
          key={toast.id}
          className="pointer-events-auto flex items-start gap-3 rounded-xl border border-slate-200/90 bg-white/95 p-3.5 shadow-[0_14px_34px_rgba(15,23,42,0.14)] backdrop-blur-2xl transition-all duration-150"
        >
          <div className="mt-0.5 shrink-0">
            <AgentSpriteCanvas
              status={AgentStatus.Completed}
              pack={activePack}
              size={24}
            />
          </div>

          <div className="min-w-0 flex-1">
            <div className="flex items-center justify-between gap-2 text-[11px] text-slate-500">
              <span className="flex items-center gap-1.5 font-medium text-slate-700">
                <BellOff className="w-3 h-3 text-emerald-600 shrink-0" />
                <span>opencode 静音提醒</span>
                <span aria-hidden="true">·</span>
                <span className="font-mono tabular-nums">{toast.timestamp}</span>
              </span>
              <button
                type="button"
                onClick={() => onDismiss(toast.id)}
                aria-label="关闭通知"
                className="rounded p-0.5 text-slate-400 hover:bg-slate-100 hover:text-slate-700 transition-colors"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            </div>

            <p className="mt-1 text-xs font-medium text-slate-900 line-clamp-2">
              {toast.sessionTitle}
            </p>

            <button
              type="button"
              onClick={() => {
                onJump(toast.sessionId, toast.subTaskId);
                onDismiss(toast.id);
              }}
              className="mt-2 inline-flex items-center gap-1 text-[11px] font-semibold text-sky-700 hover:text-sky-600 transition-colors whitespace-nowrap"
            >
              <span>跳回 {toast.targetRef}</span>
              <ExternalLink className="w-3 h-3 shrink-0" />
            </button>
          </div>
        </div>
      ))}
    </div>
  );
};
