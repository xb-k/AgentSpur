export enum AgentStatus {
  Thinking = 'thinking',
  Working = 'working',
  Confirm = 'confirm',
  Completed = 'completed',
  Error = 'error',
}

export enum TargetApp {
  OpenCodeTUI = 'opencode TUI',
  ITerm2 = 'iTerm2',
}

export type CharacterArchetype = 'glyph' | 'whale' | 'neko' | 'kitsune' | 'custom_pixel';

export interface CharacterPack {
  id: string;
  name: string;
  author: string;
  version: string;
  deepseekModel: string;
  roleDescription: string;
  archetype: CharacterArchetype;
  primaryColor: string;
  secondaryColor: string;
  isBuiltIn?: boolean;
  /** Optional 12x12 ASCII pixel matrix ('#' primary, '+' accent, '.' transparent) for custom packs */
  customBaseSprite?: string[];
}

export interface SubAgentTask {
  id: string;
  parentId: string;
  title: string;
  subagentRole: string; // e.g. "@explore" or "@general" in opencode TUI
  status: AgentStatus;
  targetApp: TargetApp;
  targetRef: string; // e.g. "iTerm2 · Tab 2 (opencode)" or "opencode TUI · 子会话 #12-B"
  itermTabIndex?: number;
  elapsed: string;
  localOffset: string;
  logLines: string[];
}

export interface MasterSession {
  id: string;
  title: string;
  engine: 'opencode' | 'DeepSeek';
  modelName: string;
  status: AgentStatus;
  targetApp: TargetApp;
  targetRef: string;
  itermTabIndex?: number;
  localPath: string;
  updatedAt: string;
  summary: string;
  logLines: string[];
  subTasks: SubAgentTask[];
}

export interface QuotaState {
  remainingUsd: number;
  totalUsd: number;
  resetTimeLabel: string;
  resetCountdown: string;
  lastRefreshedAt: string;
}

export interface SilentToastItem {
  id: string;
  sessionTitle: string;
  targetApp: TargetApp;
  targetRef: string;
  sessionId: string;
  subTaskId?: string;
  timestamp: string;
}
