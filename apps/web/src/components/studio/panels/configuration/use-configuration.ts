/**
 * Hook for managing configuration panel state.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNixConfig, useNixData } from "@/lib/use-nix-config";
import { useAgentClient } from "@/lib/agent-provider";
import { optionalValue } from "./constants";
import type {
  AwsData,
  BinaryCacheData,
  IdeData,
  SecretsData,
  StepCaData,
  ThemeData,
  UsersSettingsData,
} from "./types";

export interface UseConfigurationResult {
  // GitHub state
  githubRepo: string;
  setGithubRepo: (value: string) => void;
  githubSyncEnabled: boolean;
  setGithubSyncEnabled: (value: boolean) => void;
  savingGithub: boolean;
  saveGithub: () => Promise<void>;

  // Step CA state
  stepEnabled: boolean;
  setStepEnabled: (value: boolean) => void;
  stepCaUrl: string;
  setStepCaUrl: (value: string) => void;
  stepCaFingerprint: string;
  setStepCaFingerprint: (value: string) => void;
  fetchingFingerprint: boolean;
  fetchFingerprint: () => Promise<void>;
  stepProvisioner: string;
  setStepProvisioner: (value: string) => void;
  stepCertName: string;
  setStepCertName: (value: string) => void;
  stepPromptOnShell: boolean;
  setStepPromptOnShell: (value: boolean) => void;
  savingStepCa: boolean;
  saveStepCa: () => Promise<void>;

  // AWS state
  awsEnabled: boolean;
  setAwsEnabled: (value: boolean) => void;
  awsRegion: string;
  setAwsRegion: (value: string) => void;
  awsAccountId: string;
  setAwsAccountId: (value: string) => void;
  awsRoleName: string;
  setAwsRoleName: (value: string) => void;
  awsTrustAnchorArn: string;
  setAwsTrustAnchorArn: (value: string) => void;
  awsProfileArn: string;
  setAwsProfileArn: (value: string) => void;
  awsCacheBufferSeconds: string;
  setAwsCacheBufferSeconds: (value: string) => void;
  awsPromptOnShell: boolean;
  setAwsPromptOnShell: (value: boolean) => void;
  savingAws: boolean;
  saveAws: () => Promise<void>;

  // Theme state
  themeEnabled: boolean;
  setThemeEnabled: (value: boolean) => void;
  themePreset: string;
  setThemePreset: (value: string) => void;
  savingTheme: boolean;
  saveTheme: () => Promise<void>;

  // IDE state
  ideEnabled: boolean;
  setIdeEnabled: (value: boolean) => void;
  vscodeEnabled: boolean;
  setVscodeEnabled: (value: boolean) => void;
  savingIde: boolean;
  saveIde: () => Promise<void>;

  // Binary Cache state
  cacheEnabled: boolean;
  setCacheEnabled: (value: boolean) => void;
  cachixEnabled: boolean;
  setCachixEnabled: (value: boolean) => void;
  cachixCache: string;
  setCachixCache: (value: string) => void;
  cachixTokenPath: string;
  setCachixTokenPath: (value: string) => void;
  savingCache: boolean;
  saveCache: () => Promise<void>;

  // Derived values
  secretsEnabled: boolean;
  cachixControlsDisabled: boolean;
}

export function useConfiguration(): UseConfigurationResult {
  const { data: config } = useNixConfig();
  const client = useAgentClient();

  // Track if initial data has been loaded for each section
  const stepCaInitialized = useRef(false);
  const awsInitialized = useRef(false);
  const themeInitialized = useRef(false);
  const ideInitialized = useRef(false);
  const cacheInitialized = useRef(false);
  const githubInitialized = useRef(false);
  const { data: stepCaData, mutate: setStepCa } = useNixData<StepCaData>(
    "step-ca",
    { initialData: {} },
  );
  const { data: awsData, mutate: setAws } = useNixData<AwsData>("aws", {
    initialData: {},
  });
  const { data: themeData, mutate: setTheme } = useNixData<ThemeData>("theme", {
    initialData: {},
  });
  const { data: ideData, mutate: setIde } = useNixData<IdeData>("ide", {
    initialData: {},
  });
  const { data: secretsData } = useNixData<SecretsData>("secrets", {
    initialData: {},
  });
  const { data: usersSettingsData, mutate: setUsersSettings } =
    useNixData<UsersSettingsData>("users-settings", { initialData: {} });
  const { data: githubData, mutate: setGithub } = useNixData<string>("github", {
    initialData: "",
  });
  const { data: cacheData, mutate: setCache } = useNixData<BinaryCacheData>(
    "binary-cache",
    { initialData: {} },
  );

  // Extract config values
  const stackpanelConfig = useMemo(() => {
    if (!config || typeof config !== "object") return {} as Record<string, any>;
    const maybeStackpanel = (config as { stackpanel?: unknown }).stackpanel;
    if (maybeStackpanel && typeof maybeStackpanel === "object") {
      return maybeStackpanel as Record<string, any>;
    }
    return config as Record<string, any>;
  }, [config]);

  const stepConfig = stackpanelConfig.stepCa?.["step-ca"] ?? {};
  const awsConfig = stackpanelConfig.aws?.["roles-anywhere"] ?? {};
  const themeConfig = stackpanelConfig.theme ?? {};
  const ideConfig = stackpanelConfig.ide ?? {};
  const secretsConfig = stackpanelConfig.secrets ?? {};
  const githubConfig = stackpanelConfig.github ?? "";

  // GitHub state
  const [githubRepo, setGithubRepo] = useState("");
  const [githubSyncEnabled, setGithubSyncEnabled] = useState(true);
  const [savingGithub, setSavingGithub] = useState(false);

  // Step CA state
  const [stepEnabled, setStepEnabled] = useState(false);
  const [stepCaUrl, setStepCaUrl] = useState("");
  const [stepCaFingerprint, setStepCaFingerprint] = useState("");
  const [fetchingFingerprint, setFetchingFingerprint] = useState(false);
  const [stepProvisioner, setStepProvisioner] = useState("");
  const [stepCertName, setStepCertName] = useState("");
  const [stepPromptOnShell, setStepPromptOnShell] = useState(false);
  const [savingStepCa, setSavingStepCa] = useState(false);

  // AWS state
  const [awsEnabled, setAwsEnabled] = useState(false);
  const [awsRegion, setAwsRegion] = useState("");
  const [awsAccountId, setAwsAccountId] = useState("");
  const [awsRoleName, setAwsRoleName] = useState("");
  const [awsTrustAnchorArn, setAwsTrustAnchorArn] = useState("");
  const [awsProfileArn, setAwsProfileArn] = useState("");
  const [awsCacheBufferSeconds, setAwsCacheBufferSeconds] = useState("");
  const [awsPromptOnShell, setAwsPromptOnShell] = useState(false);
  const [savingAws, setSavingAws] = useState(false);

  // Theme state
  const [themeEnabled, setThemeEnabled] = useState(false);
  const [themePreset, setThemePreset] = useState("stackpanel");
  const [savingTheme, setSavingTheme] = useState(false);

  // IDE state
  const [ideEnabled, setIdeEnabled] = useState(false);
  const [vscodeEnabled, setVscodeEnabled] = useState(false);
  const [savingIde, setSavingIde] = useState(false);

  // Binary Cache state
  const [cacheEnabled, setCacheEnabled] = useState(false);
  const [cachixEnabled, setCachixEnabled] = useState(false);
  const [cachixCache, setCachixCache] = useState("");
  const [cachixTokenPath, setCachixTokenPath] = useState("");
  const [savingCache, setSavingCache] = useState(false);

  // Derived values
  const secretsEnabled = secretsData?.enable ?? secretsConfig?.enable ?? false;
  const cachixControlsDisabled = !cacheEnabled || !secretsEnabled;

  // Sync effects - only sync initial data once to avoid overwriting user input
  useEffect(() => {
    if (githubInitialized.current) return;
    const hasData = githubData !== undefined || githubConfig !== undefined;
    if (!hasData) return;

    githubInitialized.current = true;
    const repoValue = githubData ?? githubConfig ?? "";
    setGithubRepo(repoValue);
    setGithubSyncEnabled(!(usersSettingsData?.disable_github_sync ?? false));
  }, [githubData, githubConfig, usersSettingsData?.disable_github_sync]);

  useEffect(() => {
    if (stepCaInitialized.current) return;
    const hasData = stepCaData !== null || Object.keys(stepConfig).length > 0;
    if (!hasData && !config) return;

    stepCaInitialized.current = true;
    setStepEnabled(stepCaData?.enable ?? stepConfig?.enable ?? false);
    setStepCaUrl(stepCaData?.ca_url ?? stepConfig?.["ca-url"] ?? "");
    setStepCaFingerprint(
      stepCaData?.ca_fingerprint ?? stepConfig?.["ca-fingerprint"] ?? "",
    );
    setStepProvisioner(
      stepCaData?.provisioner ?? stepConfig?.provisioner ?? "",
    );
    setStepCertName(stepCaData?.cert_name ?? stepConfig?.["cert-name"] ?? "");
    setStepPromptOnShell(
      stepCaData?.prompt_on_shell ?? stepConfig?.["prompt-on-shell"] ?? false,
    );
  }, [stepCaData, stepConfig, config]);

  useEffect(() => {
    if (awsInitialized.current) return;
    const hasData = awsData !== null || Object.keys(awsConfig).length > 0;
    if (!hasData && !config) return;

    awsInitialized.current = true;
    const rolesAnywhere = awsData?.roles_anywhere ?? {};
    setAwsEnabled(rolesAnywhere.enable ?? awsConfig?.enable ?? false);
    setAwsRegion(rolesAnywhere.region ?? awsConfig?.region ?? "");
    setAwsAccountId(
      rolesAnywhere.account_id ?? awsConfig?.["account-id"] ?? "",
    );
    setAwsRoleName(rolesAnywhere.role_name ?? awsConfig?.["role-name"] ?? "");
    setAwsTrustAnchorArn(
      rolesAnywhere.trust_anchor_arn ?? awsConfig?.["trust-anchor-arn"] ?? "",
    );
    setAwsProfileArn(
      rolesAnywhere.profile_arn ?? awsConfig?.["profile-arn"] ?? "",
    );
    setAwsCacheBufferSeconds(
      rolesAnywhere.cache_buffer_seconds ??
        awsConfig?.["cache-buffer-seconds"] ??
        "",
    );
    setAwsPromptOnShell(
      rolesAnywhere.prompt_on_shell ?? awsConfig?.["prompt-on-shell"] ?? false,
    );
  }, [awsData, awsConfig, config]);

  useEffect(() => {
    if (themeInitialized.current) return;
    const hasData = themeData !== null || Object.keys(themeConfig).length > 0;
    if (!hasData && !config) return;

    themeInitialized.current = true;
    setThemeEnabled(themeData?.enable ?? themeConfig?.enable ?? false);
    setThemePreset(themeData?.preset ?? themeConfig?.preset ?? "stackpanel");
  }, [themeData, themeConfig, config]);

  useEffect(() => {
    if (ideInitialized.current) return;
    const hasData = ideData !== null || Object.keys(ideConfig).length > 0;
    if (!hasData && !config) return;

    ideInitialized.current = true;
    setIdeEnabled(ideData?.enable ?? ideConfig?.enable ?? false);
    setVscodeEnabled(
      ideData?.vscode?.enable ?? ideConfig?.vscode?.enable ?? false,
    );
  }, [ideData, ideConfig, config]);

  useEffect(() => {
    if (cacheInitialized.current) return;
    if (cacheData === null) return;

    cacheInitialized.current = true;
    setCacheEnabled(cacheData?.enable ?? false);
    setCachixEnabled(cacheData?.cachix?.enable ?? false);
    setCachixCache(cacheData?.cachix?.cache ?? "");
    setCachixTokenPath(cacheData?.cachix?.token_path ?? "");
  }, [cacheData]);

  // Fetch CA fingerprint from Step CA server
  const fetchFingerprint = useCallback(async () => {
    if (!stepCaUrl || fetchingFingerprint) return;

    // Validate URL format
    try {
      new URL(stepCaUrl);
    } catch {
      return;
    }

    setFetchingFingerprint(true);
    try {
      // Call the agent to fetch the fingerprint from the CA
      const response = await client.post<{
        fingerprint?: string;
        error?: string;
      }>("/api/exec", {
        command: "step",
        args: ["ca", "root", stepCaUrl, "--fingerprint"],
      });

      // The fingerprint is usually in stdout
      if (response && typeof response === "object" && "stdout" in response) {
        const stdout = (response as { stdout?: string }).stdout?.trim();
        if (stdout && stdout.length > 0 && !stdout.includes("error")) {
          setStepCaFingerprint(stdout);
        }
      }
    } catch (err) {
      console.warn("Failed to fetch CA fingerprint:", err);
    } finally {
      setFetchingFingerprint(false);
    }
  }, [stepCaUrl, fetchingFingerprint, client]);

  // Auto-fetch fingerprint when CA URL changes and looks valid
  useEffect(() => {
    if (!stepCaUrl || stepCaFingerprint) return;

    // Validate URL format
    try {
      const url = new URL(stepCaUrl);
      // Only fetch if URL looks complete (has protocol and host)
      if (url.protocol && url.host) {
        // Debounce the fetch
        const timer = setTimeout(() => {
          fetchFingerprint();
        }, 1000);
        return () => clearTimeout(timer);
      }
    } catch {
      // Invalid URL, don't fetch
    }
  }, [stepCaUrl, stepCaFingerprint, fetchFingerprint]);

  // Save callbacks
  const saveGithub = useCallback(async () => {
    if (savingGithub) return;
    setSavingGithub(true);
    try {
      await setGithub(githubRepo.trim());
      await setUsersSettings({
        disable_github_sync: !githubSyncEnabled,
      });
    } finally {
      setSavingGithub(false);
    }
  }, [
    githubRepo,
    githubSyncEnabled,
    savingGithub,
    setGithub,
    setUsersSettings,
  ]);

  const saveStepCa = useCallback(async () => {
    if (savingStepCa) return;
    setSavingStepCa(true);
    try {
      await setStepCa({
        ...(stepCaData ?? {}),
        enable: stepEnabled,
        ca_url: optionalValue(stepCaUrl),
        ca_fingerprint: optionalValue(stepCaFingerprint),
        provisioner: optionalValue(stepProvisioner),
        cert_name: optionalValue(stepCertName),
        prompt_on_shell: stepPromptOnShell,
      });
    } finally {
      setSavingStepCa(false);
    }
  }, [
    savingStepCa,
    setStepCa,
    stepCaData,
    stepEnabled,
    stepCaUrl,
    stepCaFingerprint,
    stepProvisioner,
    stepCertName,
    stepPromptOnShell,
  ]);

  const saveAws = useCallback(async () => {
    if (savingAws) return;
    setSavingAws(true);
    try {
      await setAws({
        ...(awsData ?? {}),
        roles_anywhere: {
          ...(awsData?.roles_anywhere ?? {}),
          enable: awsEnabled,
          region: optionalValue(awsRegion),
          account_id: optionalValue(awsAccountId),
          role_name: optionalValue(awsRoleName),
          trust_anchor_arn: optionalValue(awsTrustAnchorArn),
          profile_arn: optionalValue(awsProfileArn),
          cache_buffer_seconds: optionalValue(awsCacheBufferSeconds),
          prompt_on_shell: awsPromptOnShell,
        },
      });
    } finally {
      setSavingAws(false);
    }
  }, [
    awsAccountId,
    awsCacheBufferSeconds,
    awsData,
    awsEnabled,
    awsProfileArn,
    awsPromptOnShell,
    awsRegion,
    awsRoleName,
    awsTrustAnchorArn,
    savingAws,
    setAws,
  ]);

  const saveTheme = useCallback(async () => {
    if (savingTheme) return;
    setSavingTheme(true);
    try {
      await setTheme({
        ...(themeData ?? {}),
        enable: themeEnabled,
        preset: themePreset as ThemeData["preset"],
      });
    } finally {
      setSavingTheme(false);
    }
  }, [savingTheme, setTheme, themeData, themeEnabled, themePreset]);

  const saveIde = useCallback(async () => {
    if (savingIde) return;
    setSavingIde(true);
    try {
      await setIde({
        ...(ideData ?? {}),
        enable: ideEnabled,
        vscode: {
          ...(ideData?.vscode ?? {}),
          enable: vscodeEnabled,
        },
      });
    } finally {
      setSavingIde(false);
    }
  }, [ideData, ideEnabled, savingIde, setIde, vscodeEnabled]);

  const saveCache = useCallback(async () => {
    if (savingCache) return;
    setSavingCache(true);
    try {
      await setCache({
        ...(cacheData ?? {}),
        enable: cacheEnabled,
        cachix: {
          ...(cacheData?.cachix ?? {}),
          enable: cachixEnabled,
          cache: optionalValue(cachixCache),
          token_path: optionalValue(cachixTokenPath),
        },
      });
    } finally {
      setSavingCache(false);
    }
  }, [
    cacheData,
    cacheEnabled,
    cachixCache,
    cachixEnabled,
    cachixTokenPath,
    savingCache,
    setCache,
  ]);

  return {
    // GitHub
    githubRepo,
    setGithubRepo,
    githubSyncEnabled,
    setGithubSyncEnabled,
    savingGithub,
    saveGithub,

    // Step CA
    stepEnabled,
    setStepEnabled,
    stepCaUrl,
    setStepCaUrl,
    stepCaFingerprint,
    setStepCaFingerprint,
    fetchingFingerprint,
    fetchFingerprint,
    stepProvisioner,
    setStepProvisioner,
    stepCertName,
    setStepCertName,
    stepPromptOnShell,
    setStepPromptOnShell,
    savingStepCa,
    saveStepCa,

    // AWS
    awsEnabled,
    setAwsEnabled,
    awsRegion,
    setAwsRegion,
    awsAccountId,
    setAwsAccountId,
    awsRoleName,
    setAwsRoleName,
    awsTrustAnchorArn,
    setAwsTrustAnchorArn,
    awsProfileArn,
    setAwsProfileArn,
    awsCacheBufferSeconds,
    setAwsCacheBufferSeconds,
    awsPromptOnShell,
    setAwsPromptOnShell,
    savingAws,
    saveAws,

    // Theme
    themeEnabled,
    setThemeEnabled,
    themePreset,
    setThemePreset,
    savingTheme,
    saveTheme,

    // IDE
    ideEnabled,
    setIdeEnabled,
    vscodeEnabled,
    setVscodeEnabled,
    savingIde,
    saveIde,

    // Binary Cache
    cacheEnabled,
    setCacheEnabled,
    cachixEnabled,
    setCachixEnabled,
    cachixCache,
    setCachixCache,
    cachixTokenPath,
    setCachixTokenPath,
    savingCache,
    saveCache,

    // Derived values
    secretsEnabled,
    cachixControlsDisabled,
  };
}
