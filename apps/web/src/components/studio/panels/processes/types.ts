/**
 * Process Compose Panel Types
 *
 * Types for configuring process-compose processes from multiple sources:
 * - Apps (with tasks.dev.command)
 * - Scripts (from stackpanel.scripts)
 * - Tasks (via turbo run -F)
 * - Custom user-defined processes
 */

// =============================================================================
// Process Source Types
// =============================================================================

/** Process source type identifier */
export type ProcessSourceType = "app" | "script" | "task" | "custom" | "infra" | "service";

/** A selectable process from any source */
export interface ProcessSource {
  /** Unique identifier */
  id: string;
  /** Source type */
  type: ProcessSourceType;
  /** Display name / process name */
  name: string;
  /** Command to run */
  command: string;
  /** Working directory (relative to project root) */
  workingDir?: string;
  /** Whether this process is enabled/included in config */
  enabled: boolean;
  /** Whether to auto-start this process (if false, shows in TUI but doesn't start) */
  autoStart: boolean;
  /** Whether to use entrypoint script (handles env setup, secrets, etc.) */
  useEntrypoint: boolean;
  /** Optional namespace for grouping */
  namespace?: string;

  // Source-specific metadata
  /** For apps: the app name in stackpanel.apps */
  appName?: string;
  /** For tasks: the task name (e.g., "dev", "build", "test") */
  taskName?: string;
  /** For tasks: the package filter (-F value) */
  packageFilter?: string;
  /** For scripts: the script name in stackpanel.scripts */
  scriptName?: string;
  /** For custom: user-provided description */
  description?: string;
  /** For services: the port this service listens on */
  port?: number;
  /** For services: the data directory path */
  dataDir?: string;
  /** For services: human-readable display name */
  displayName?: string;
}

// =============================================================================
// Process Compose Configuration Types (matches upstream schema)
// =============================================================================

/** Condition for process dependencies */
export type ProcessCondition =
  | "process_completed"
  | "process_completed_successfully"
  | "process_healthy"
  | "process_started";

/** Restart policy for availability */
export type RestartPolicy = "always" | "on_failure" | "exit_on_failure" | "no";

/** Availability configuration */
export interface AvailabilityConfig {
  restart?: RestartPolicy;
  backoff_seconds?: number;
  max_restarts?: number;
}

/** Exec probe configuration */
export interface ExecProbe {
  command: string;
}

/** HTTP GET probe configuration */
export interface HttpGetProbe {
  host: string;
  port: number | string;
  path?: string;
  scheme?: "http" | "https";
}

/** Health/readiness probe configuration */
export interface ProbeConfig {
  exec?: ExecProbe;
  http_get?: HttpGetProbe;
  initial_delay_seconds?: number;
  period_seconds?: number;
  timeout_seconds?: number;
  success_threshold?: number;
  failure_threshold?: number;
}

/** Dependency configuration */
export interface DependsOnConfig {
  condition: ProcessCondition;
}

/** Single process configuration (matches process-compose YAML schema) */
export interface ProcessConfig {
  command: string;
  working_dir?: string | null;
  namespace?: string;
  environment?: string[];
  is_tty?: boolean;
  is_elevated?: boolean;
  /** If true, process won't start automatically but shows in TUI for manual start */
  disabled?: boolean;
  depends_on?: Record<string, DependsOnConfig>;
  availability?: AvailabilityConfig;
  readiness_probe?: ProbeConfig;
  liveness_probe?: ProbeConfig;
  /** Variables for Go template rendering */
  vars?: Record<string, string | number | boolean>;
  /** Description shown in TUI */
  description?: string;
}

/** Shell/backend configuration */
export interface ShellConfig {
  shell_command: string;
  shell_argument?: string;
}

/** Full process-compose.yaml configuration */
export interface ProcessComposeYamlConfig {
  version: string;
  processes: Record<string, ProcessConfig>;
  environment?: string[];
  vars?: Record<string, string | number | boolean>;
  shell?: ShellConfig;
  is_strict?: boolean;
  ordered_shutdown?: boolean;
  disable_env_expansion?: boolean;
}

// =============================================================================
// Stackpanel-specific Configuration Types
// =============================================================================

/** Format watcher settings */
export interface FormatWatcherSettings {
  enable: boolean;
  extensions: string[];
  command?: string;
}

/** Global process-compose settings (from stackpanel.process-compose) */
export interface ProcessComposeSettings {
  /** Enable process-compose integration */
  enable: boolean;
  /** Command name (default: "dev") */
  commandName: string;
  /** Format watcher configuration */
  formatWatcher: FormatWatcherSettings;
  /** Global environment variables */
  environment: Record<string, string>;
}

/** Default settings */
export const DEFAULT_SETTINGS: ProcessComposeSettings = {
  enable: true,
  commandName: "dev",
  formatWatcher: {
    enable: true,
    extensions: [
      "ts",
      "tsx",
      "js",
      "jsx",
      "json",
      "md",
      "css",
      "scss",
      "html",
      "nix",
      "go",
      "rs",
      "py",
    ],
  },
  environment: {},
};

/** Default extensions for format watcher */
export const DEFAULT_FORMAT_EXTENSIONS = [
  "ts",
  "tsx",
  "js",
  "jsx",
  "json",
  "md",
  "css",
  "scss",
  "html",
  "nix",
  "go",
  "rs",
  "py",
];

// =============================================================================
// Live Status Types (from agent)
// =============================================================================

/** Process status values */
export type ProcessStatusValue =
  | "Running"
  | "Completed"
  | "Pending"
  | "Failed"
  | "Stopping"
  | "Disabled"
  | "Skipped"
  | "Foreground"
  | "Launching"
  | "Restarting"
  | "Terminated";

/** Live process status from agent */
export interface ProcessStatus {
  name: string;
  namespace?: string;
  status: ProcessStatusValue;
  isRunning: boolean;
  pid?: number;
  exitCode?: number;
  restarts?: number;
  systemTime?: string;
}

// =============================================================================
// UI State Types
// =============================================================================

/** Tab identifiers for source selection */
export type SourceTab = "apps" | "services" | "scripts" | "tasks" | "custom";

/** Full UI state for the processes panel */
export interface ProcessesState {
  /** All available/selected process sources */
  sources: ProcessSource[];
  /** Global settings */
  settings: ProcessComposeSettings;
  /** Live status by process name */
  statuses: Record<string, ProcessStatus>;
  /** Currently active source tab */
  activeTab: SourceTab;
  /** Search query */
  searchQuery: string;
}

/** Initial state */
export const INITIAL_STATE: ProcessesState = {
  sources: [],
  settings: DEFAULT_SETTINGS,
  statuses: {},
  activeTab: "apps",
  searchQuery: "",
};

// =============================================================================
// Nix Generation Types
// =============================================================================

/** Nix output format options */
export type NixOutputFormat = "inline" | "partial" | "full";

/** Generated Nix configuration */
export interface GeneratedNixConfig {
  /** The Nix expression content */
  content: string;
  /** Output format used */
  format: NixOutputFormat;
  /** Path where partial would be written (for partial format) */
  partialPath?: string;
}

// =============================================================================
// Utility Types
// =============================================================================

/** Props for source tab components */
export interface SourceTabProps {
  sources: ProcessSource[];
  statuses: Record<string, ProcessStatus>;
  onToggle: (id: string, enabled: boolean) => void;
  onEdit?: (id: string) => void;
  searchQuery?: string;
}

/** Props for process card component */
export interface ProcessCardProps {
  source: ProcessSource;
  status?: ProcessStatus;
  onToggle: (enabled: boolean) => void;
  onEdit?: () => void;
  onRemove?: () => void;
  showRemove?: boolean;
}
