// Generated from nix/stackpanel/db - DO NOT EDIT
// Regenerate: ./nix/stackpanel/db/generate-types.sh ts

export interface StackpanelDB {
    /**
     * AWS configuration including Roles Anywhere for certificate-based authentication
     */
    aws?: AwsAws;
    /**
     * Database connection and configuration settings
     */
    databases?: DatabasesDatabases;
    /**
     * DNS records and domain configuration
     */
    dns?: DNSDNS;
    /**
     * Extensions and plugins configuration
     */
    extensions?: ExtensionsExtensions;
    /**
     * Auto-generated GitHub collaborators data
     */
    githubCollaborators?: GithubCollaboratorsGithubCollaborators;
    /**
     * Onboarding configuration for new team members
     */
    onboarding?: OnboardingOnboarding;
    /**
     * Secrets management configuration
     */
    secrets?: SecretsSecrets;
    /**
     * Global development services configuration
     */
    services?: ServicesServices;
    /**
     * Shell-specific settings and configurations
     */
    shells?: ShellsShells;
    /**
     * Step CA certificate management configuration for local HTTPS
     */
    stepCa?: StepCAStepCA;
    /**
     * Theme and Starship prompt configuration
     */
    theme?: ThemeTheme;
    /**
     * Map of username to user configuration
     */
    users?: { [key: string]: UsersUser };
    [property: string]: any;
}

/**
 * AWS configuration including Roles Anywhere for certificate-based authentication
 */
export interface AwsAws {
    /**
     * AWS Roles Anywhere configuration
     */
    "roles-anywhere": RolesAnywhere;
    [property: string]: any;
}

/**
 * AWS Roles Anywhere configuration
 */
export interface RolesAnywhere {
    /**
     * AWS account ID
     */
    "account-id": string;
    /**
     * Seconds before expiry to refresh cached credentials
     */
    "cache-buffer-seconds"?: string;
    /**
     * Enable AWS Roles Anywhere cert auth
     */
    enable?: boolean;
    /**
     * AWS Roles Anywhere profile ARN
     */
    "profile-arn": string;
    /**
     * Prompt for AWS cert-auth setup on shell entry if not configured
     */
    "prompt-on-shell"?: boolean;
    /**
     * AWS region
     */
    region?: string;
    /**
     * IAM role name to assume
     */
    "role-name": string;
    /**
     * AWS Roles Anywhere trust anchor ARN
     */
    "trust-anchor-arn": string;
    [property: string]: any;
}

/**
 * Database connection and configuration settings
 */
export interface DatabasesDatabases {
    /**
     * Database configurations by environment/name
     */
    databases: { [key: string]: Database };
    /**
     * Default database configuration to use
     */
    default?: string;
    [property: string]: any;
}

/**
 * Database instance configuration
 */
export interface Database {
    /**
     * Run migrations on startup
     */
    "auto-migrate"?: boolean;
    /**
     * Database connection settings
     */
    connection: Connection;
    /**
     * Path to migrations directory
     */
    "migrations-path"?: string;
    /**
     * Connection pool settings
     */
    pool: Pool;
    /**
     * Path to seed data directory
     */
    "seeds-path"?: null | string;
    /**
     * Database type
     */
    type?: DatabaseType;
    [property: string]: any;
}

/**
 * Database connection settings
 */
export interface Connection {
    /**
     * Database name
     */
    database: string;
    /**
     * Database host
     */
    host?: string;
    /**
     * Environment variable containing the password
     */
    "password-env"?: null | string;
    /**
     * Database port
     */
    port?: number;
    /**
     * Enable SSL/TLS connection
     */
    ssl?: boolean;
    /**
     * SSL mode for PostgreSQL connections
     */
    "ssl-mode"?: SSLMode;
    /**
     * Database username
     */
    username?: string;
    [property: string]: any;
}

/**
 * SSL mode for PostgreSQL connections
 */
export enum SSLMode {
    Allow = "allow",
    Disable = "disable",
    Prefer = "prefer",
    Require = "require",
    VerifyCA = "verify-ca",
    VerifyFull = "verify-full",
}

/**
 * Connection pool settings
 */
export interface Pool {
    /**
     * Connection timeout in seconds
     */
    "connection-timeout"?: number;
    /**
     * Idle connection timeout in seconds
     */
    "idle-timeout"?: number;
    /**
     * Maximum connections in pool
     */
    max?: number;
    /**
     * Minimum connections in pool
     */
    min?: number;
    [property: string]: any;
}

/**
 * Database type
 */
export enum DatabaseType {
    Mongodb = "mongodb",
    Mysql = "mysql",
    Postgresql = "postgresql",
    Sqlite = "sqlite",
}

/**
 * DNS records and domain configuration
 */
export interface DNSDNS {
    /**
     * Default TTL for records (seconds)
     */
    "default-ttl"?: number;
    /**
     * DNS zones/domains configuration
     */
    zones: { [key: string]: Zone };
    [property: string]: any;
}

/**
 * DNS zone configuration
 */
export interface Zone {
    /**
     * Domain name (e.g., 'example.com')
     */
    domain: string;
    /**
     * Whether stackpanel manages this zone
     */
    managed?: boolean;
    /**
     * DNS provider
     */
    provider: Provider;
    /**
     * List of DNS records for this zone
     */
    records?: { [key: string]: any }[];
    /**
     * Provider-specific zone ID (if required)
     */
    "zone-id"?: null | string;
    [property: string]: any;
}

/**
 * DNS provider
 */
export enum Provider {
    Cloudflare = "cloudflare",
    Digitalocean = "digitalocean",
    Manual = "manual",
    Namecheap = "namecheap",
    Route53 = "route53",
}

/**
 * Extensions and plugins configuration
 */
export interface ExtensionsExtensions {
    /**
     * Automatically check for extension updates
     */
    "auto-update"?: boolean;
    /**
     * Enable extensions system
     */
    enabled?: boolean;
    /**
     * Installed extensions by key
     */
    extensions: { [key: string]: Extension };
    /**
     * Default extension registry URL
     */
    registry?: string;
    [property: string]: any;
}

/**
 * Extension configuration
 */
export interface Extension {
    /**
     * Extension-specific configuration options
     */
    config?: { [key: string]: any };
    /**
     * Other extensions this depends on
     */
    dependencies?: string[];
    /**
     * Whether this extension is enabled
     */
    enabled?: boolean;
    /**
     * Display name of the extension
     */
    name: string;
    /**
     * Load order priority (lower = earlier)
     */
    priority?: number;
    /**
     * Extension source configuration
     */
    source: Source;
    /**
     * Tags for categorizing/filtering extensions
     */
    tags?: string[];
    /**
     * Version constraint (e.g., '^1.0.0', '~2.3', 'latest')
     */
    version?: null | string;
    [property: string]: any;
}

/**
 * Extension source configuration
 */
export interface Source {
    /**
     * NPM package name for npm source type
     */
    package?: null | string;
    /**
     * Local path for local source type
     */
    path?: null | string;
    /**
     * Git ref (branch, tag, commit) for github source type
     */
    ref?: null | string;
    /**
     * GitHub repository (owner/repo) for github source type
     */
    repo?: null | string;
    /**
     * Source type for the extension
     */
    type: SourceType;
    /**
     * URL for url source type
     */
    url?: null | string;
    [property: string]: any;
}

/**
 * Source type for the extension
 */
export enum SourceType {
    Github = "github",
    Local = "local",
    Npm = "npm",
    URL = "url",
}

/**
 * Auto-generated GitHub collaborators data
 */
export interface GithubCollaboratorsGithubCollaborators {
    /**
     * Metadata about this generated file
     */
    _meta: Meta;
    /**
     * Map of username to collaborator data
     */
    collaborators: { [key: string]: Collaborator };
    [property: string]: any;
}

/**
 * Metadata about this generated file
 */
export interface Meta {
    /**
     * ISO 8601 timestamp of when this file was generated
     */
    generatedAt: Date;
    /**
     * GitHub repository source (e.g., github:owner/repo)
     */
    source: string;
    [property: string]: any;
}

/**
 * A GitHub collaborator
 */
export interface Collaborator {
    /**
     * GitHub user ID
     */
    id: number;
    /**
     * Whether this user has admin permissions
     */
    isAdmin?: boolean;
    /**
     * GitHub username/login
     */
    login: string;
    /**
     * SSH public keys from GitHub
     */
    publicKeys?: string[];
    /**
     * Repository permission level
     */
    role: Role;
    [property: string]: any;
}

/**
 * Repository permission level
 */
export enum Role {
    Admin = "admin",
    Maintain = "maintain",
    Read = "read",
    Triage = "triage",
    Write = "write",
}

/**
 * Onboarding configuration for new team members
 */
export interface OnboardingOnboarding {
    /**
     * Automatically run onboarding on first shell entry
     */
    "auto-run"?: boolean;
    /**
     * Categories for organizing onboarding steps
     */
    categories: { [key: string]: OnboardingOnboardingCategory };
    /**
     * Message shown when onboarding is complete
     */
    "completion-message"?: string;
    /**
     * Enable onboarding system
     */
    enable?: boolean;
    /**
     * Persist completed steps across shell sessions
     */
    "persist-state"?: boolean;
    /**
     * Path to store onboarding state
     */
    "state-file"?: string;
    /**
     * Onboarding steps
     */
    steps: { [key: string]: OnboardingOnboardingStep };
    /**
     * Welcome message shown to new team members
     */
    "welcome-message"?: string;
    [property: string]: any;
}

/**
 * Onboarding category configuration
 */
export interface OnboardingOnboardingCategory {
    /**
     * Description of what this category covers
     */
    description?: null | string;
    /**
     * Icon for the category (emoji or Nerd Font icon)
     */
    icon?: null | string;
    /**
     * Order in which this category appears
     */
    order?: number;
    /**
     * Display title for the category
     */
    title: string;
    [property: string]: any;
}

/**
 * Onboarding step configuration
 */
export interface OnboardingOnboardingStep {
    /**
     * Category/group for organizing steps
     */
    category?: string;
    /**
     * Command to verify step completion (exit 0 = complete)
     */
    "check-command"?: null | string;
    /**
     * Command to run (for 'command' type steps)
     */
    command?: null | string;
    /**
     * List of step IDs that must be completed before this step
     */
    "depends-on"?: string[];
    /**
     * Detailed description of what this step accomplishes
     */
    description?: null | string;
    /**
     * Environments where this step applies
     */
    env?: string[];
    /**
     * Unique identifier for this step
     */
    id: string;
    /**
     * Order in which this step should be presented
     */
    order?: number;
    /**
     * Whether this step is required
     */
    required?: boolean;
    /**
     * Condition command - skip step if exits 0
     */
    "skip-if"?: null | string;
    /**
     * Display title for the step
     */
    title: string;
    /**
     * Type of onboarding step
     */
    type?: StepType;
    /**
     * URL to open (for 'link' type steps)
     */
    url?: null | string;
    [property: string]: any;
}

/**
 * Type of onboarding step
 */
export enum StepType {
    Check = "check",
    Command = "command",
    Link = "link",
    Manual = "manual",
    Prompt = "prompt",
}

/**
 * Secrets management configuration
 */
export interface SecretsSecrets {
    /**
     * Code generation settings per target
     */
    codegen: { [key: string]: Codegen };
    /**
     * Enable secrets management
     */
    enable?: boolean;
    /**
     * Environment-specific secrets configurations
     */
    environments: { [key: string]: Environment };
    /**
     * Directory where SOPS-encrypted secrets are stored
     */
    "input-directory"?: string;
    [property: string]: any;
}

/**
 * Code generation settings for a target language
 */
export interface Codegen {
    /**
     * Output directory for generated code (relative to project root)
     */
    directory: string;
    /**
     * Programming language for generated code
     */
    language: Language;
    /**
     * Name of the generated code package
     */
    name: string;
    [property: string]: any;
}

/**
 * Programming language for generated code
 */
export enum Language {
    Go = "go",
    Typescript = "typescript",
}

/**
 * Environment-specific secrets configuration
 */
export interface Environment {
    /**
     * Name of the environment (e.g., 'production', 'staging')
     */
    name: string;
    /**
     * AGE public keys that can decrypt secrets for this environment
     */
    "public-keys"?: string[];
    /**
     * List of SOPS-encrypted source files for this environment (without .yaml extension)
     */
    sources?: string[];
    [property: string]: any;
}

/**
 * Global development services configuration
 */
export interface ServicesServices {
    /**
     * Caddy reverse proxy configuration
     */
    caddy: Caddy;
    /**
     * Minio S3-compatible service configuration
     */
    minio: Minio;
    /**
     * PostgreSQL service configuration
     */
    postgres: Postgres;
    /**
     * Project name for database/site registration
     */
    "project-name"?: string;
    /**
     * Redis service configuration
     */
    redis: Redis;
    [property: string]: any;
}

/**
 * Caddy reverse proxy configuration
 */
export interface Caddy {
    /**
     * Enable Caddy reverse proxy
     */
    enable?: boolean;
    /**
     * Sites to register with Caddy (domain -> config)
     */
    sites: { [key: string]: Site };
    [property: string]: any;
}

/**
 * Caddy site configuration
 */
export interface Site {
    /**
     * Enable TLS for this site
     */
    tls?: boolean;
    /**
     * Upstream address (e.g., 'localhost:3000')
     */
    upstream: string;
    [property: string]: any;
}

/**
 * Minio S3-compatible service configuration
 */
export interface Minio {
    /**
     * Buckets to create on startup
     */
    buckets?: string[];
    /**
     * Minio console port. If null, uses computed port from stackpanel.ports
     */
    "console-port"?: number | null;
    /**
     * Enable Minio (S3-compatible) service
     */
    enable?: boolean;
    /**
     * Minio API port. If null, uses computed port from stackpanel.ports
     */
    port?: number | null;
    [property: string]: any;
}

/**
 * PostgreSQL service configuration
 */
export interface Postgres {
    /**
     * List of databases to create for this project
     */
    databases?: string[];
    /**
     * Enable PostgreSQL service
     */
    enable?: boolean;
    /**
     * PostgreSQL extensions to enable
     */
    extensions?: string[];
    /**
     * PostgreSQL port. If null, uses computed port from stackpanel.ports
     */
    port?: number | null;
    /**
     * PostgreSQL version (e.g., '15', '16', '17')
     */
    version?: string;
    [property: string]: any;
}

/**
 * Redis service configuration
 */
export interface Redis {
    /**
     * Enable Redis service
     */
    enable?: boolean;
    /**
     * Maximum memory limit for Redis
     */
    maxmemory?: string;
    /**
     * Eviction policy when maxmemory is reached
     */
    "maxmemory-policy"?: string;
    /**
     * Redis port. If null, uses computed port from stackpanel.ports
     */
    port?: number | null;
    [property: string]: any;
}

/**
 * Shell-specific settings and configurations
 */
export interface ShellsShells {
    /**
     * Bash-specific settings
     */
    bash?: { [key: string]: any };
    /**
     * Common settings applied to all shells
     */
    common?: { [key: string]: any };
    /**
     * Default shell type
     */
    "default-shell"?: DefaultShell;
    /**
     * Fish-specific settings
     */
    fish?: { [key: string]: any };
    /**
     * Shell hooks to run on initialization
     */
    hooks?: { [key: string]: any }[];
    /**
     * Directories to append to PATH
     */
    "path-append"?: string[];
    /**
     * Directories to prepend to PATH
     */
    "path-prepend"?: string[];
    /**
     * Zsh-specific settings
     */
    zsh?: { [key: string]: any };
    [property: string]: any;
}

/**
 * Default shell type
 */
export enum DefaultShell {
    Bash = "bash",
    Fish = "fish",
    Nushell = "nushell",
    Zsh = "zsh",
}

/**
 * Step CA certificate management configuration for local HTTPS
 */
export interface StepCAStepCA {
    /**
     * Step CA certificate management configuration
     */
    "step-ca": StepCA;
    [property: string]: any;
}

/**
 * Step CA certificate management configuration
 */
export interface StepCA {
    /**
     * Step CA root certificate fingerprint for verification
     */
    "ca-fingerprint": string;
    /**
     * Step CA server URL (e.g., https://ca.internal:443)
     */
    "ca-url": string;
    /**
     * Common name for the device certificate
     */
    "cert-name"?: string;
    /**
     * Enable Step CA certificate management
     */
    enable?: boolean;
    /**
     * Prompt for certificate setup on shell entry if not configured
     */
    "prompt-on-shell"?: boolean;
    /**
     * Step CA provisioner name
     */
    provisioner?: string;
    [property: string]: any;
}

/**
 * Theme and Starship prompt configuration
 */
export interface ThemeTheme {
    /**
     * Color scheme configuration
     */
    colors: Colors;
    /**
     * Use minimal prompt (fewer segments)
     */
    minimal?: boolean;
    /**
     * Theme name
     */
    name?: string;
    /**
     * Use Nerd Font icons in prompt
     */
    "nerd-font"?: boolean;
    /**
     * Starship prompt configuration
     */
    starship: Starship;
    [property: string]: any;
}

/**
 * Color scheme configuration
 */
export interface Colors {
    /**
     * Error/negative color
     */
    error?: string;
    /**
     * Muted/subtle color
     */
    muted?: string;
    /**
     * Primary accent color
     */
    primary?: string;
    /**
     * Secondary accent color
     */
    secondary?: string;
    /**
     * Success/positive color
     */
    success?: string;
    /**
     * Warning color
     */
    warning?: string;
    [property: string]: any;
}

/**
 * Starship prompt configuration
 */
export interface Starship {
    /**
     * Add blank line before prompt
     */
    add_newline?: boolean;
    /**
     * Timeout for commands (ms)
     */
    command_timeout?: number;
    /**
     * Continuation prompt for multi-line input
     */
    continuation_prompt?: string;
    /**
     * Custom prompt format string
     */
    format?: null | string;
    /**
     * Right-side prompt format
     */
    right_format?: null | string;
    /**
     * Timeout for directory scanning (ms)
     */
    scan_timeout?: number;
    [property: string]: any;
}

/**
 * A team member with access to the project
 */
export interface UsersUser {
    /**
     * GitHub username
     */
    github?: null | string;
    /**
     * Display name of the user
     */
    name: string;
    /**
     * SSH or AGE public keys for encryption
     */
    "public-keys"?: string[];
    /**
     * Environments this user can access secrets for
     */
    "secrets-allowed-environments"?: SecretsAllowedEnvironment[];
    [property: string]: any;
}

export enum SecretsAllowedEnvironment {
    Dev = "dev",
    Production = "production",
    Staging = "staging",
}
