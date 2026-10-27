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

export type AutoFocusWindowTarget =
  | 'opencode-tui'
  | 'iterm-all'
  | 'iterm-tab-0'
  | 'iterm-tab-1'
  | 'iterm-tab-2'
  | 'iterm-tab-3';

export type CharacterArchetype =
  | 'droplet'
  | 'glyph'
  | 'whale'
  | 'neko'
  | 'kitsune'
  | 'custom_pixel';

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
  subagentRole: string;
  status: AgentStatus;
  /** Unix ms timestamp from opencode.db (part.time_created / permission.time_created) when entering current status */
  stateEnteredAt: number;
  /** Exact opencode.db table & row provenance */
  dbRecordRef: string;
  targetApp: TargetApp;
  targetRef: string;
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
  /** Unix ms timestamp from opencode.db (part.time_created / permission.time_created / session.time_updated) when entering current status */
  stateEnteredAt: number;
  /** Exact opencode.db table & row provenance */
  dbRecordRef: string;
  targetApp: TargetApp;
  targetRef: string;
  itermTabIndex?: number;
  localPath: string;
  updatedAt: string;
  duration?: string;
  summary: string;
  logLines: string[];
  subTasks: SubAgentTask[];
}

export interface WeeklyEfficiencyPoint {
  day: string;
  dateShort: string;
  tasksPerHour: number;
  avgSeconds: number;
  completedCount: number;
  isToday?: boolean;
}

export interface OpencodeDbTelemetry {
  dbPath: string;
  activeReasoningParts: number;
  activeToolParts: number;
  pendingPermissions: number;
  subAgentSessionsCount: number;
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
