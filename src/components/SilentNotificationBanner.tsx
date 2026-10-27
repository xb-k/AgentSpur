import React from 'react';
import { BellOff, X } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { AgentStatus, CharacterPack, SilentToastItem } from '../types/agent';
import { AgentSpriteCanvas } from './AgentSpriteCanvas';
import { AgentSpurLogo } from './AgentSpurLogo';

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
  return (
    <div
      aria-live="polite"
      className="fixed top-11 right-5 z-50 flex flex-col gap-2 w-76 max-w-[calc(100vw-2.5rem)] pointer-events-none"
    >
      <AnimatePresence initial={false}>
        {toasts.map((toast) => (
          <motion.div
            key={toast.id}
            initial={{ opacity: 0, y: -8, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -6, scale: 0.97 }}
            transition={{ duration: 0.18, ease: [0.16, 1, 0.3, 1] }}
            className="pointer-events-auto flex items-center gap-3 rounded-2xl border border-black/[0.06] bg-white/90 px-3.5 py-2.5 shadow-[0_16px_40px_-10px_rgba(15,23,42,0.14)] backdrop-blur-3xl"
          >
            <AgentSpriteCanvas
              status={AgentStatus.Completed}
              pack={activePack}
              size={22}
            />

            <button
              type="button"
              onClick={() => {
                onJump(toast.sessionId, toast.subTaskId);
                onDismiss(toast.id);
              }}
              className="min-w-0 flex-1 text-left group"
            >
              <div className="flex items-center gap-1.5 text-[11px] text-slate-400">
                <AgentSpurLogo size={13} />
                <span className="font-medium text-slate-600">AgentSpur</span>
                <span aria-hidden="true">·</span>
                <BellOff className="w-3 h-3 text-sky-500 shrink-0" />
                <span>静音提醒</span>
                <span aria-hidden="true">·</span>
                <span className="font-mono tabular-nums">{toast.timestamp}</span>
              </div>
              <p className="mt-0.5 truncate text-xs font-medium text-slate-900 group-hover:text-sky-700 transition-colors">
                {toast.sessionTitle}
              </p>
            </button>

            <button
              type="button"
              onClick={() => onDismiss(toast.id)}
              aria-label="关闭通知"
              className="rounded-full border border-transparent p-1 text-slate-400 hover:bg-slate-100/85 hover:border-slate-200/70 hover:text-slate-700 transition-all shrink-0 cursor-pointer"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </motion.div>
        ))}
      </AnimatePresence>
    </div>
  );
};
