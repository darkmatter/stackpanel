"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@ui/select";
import { Switch } from "@ui/switch";
import {
	AlertTriangle,
	Check,
	Github,
	Lock,
	Settings,
	Shield,
	Terminal,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useNixConfig, useNixData } from "@/lib/use-nix-config";

type StepCaData = {
	enable?: boolean;
	ca_url?: string;
	ca_fingerprint?: string;
	cert_name?: string;
	provisioner?: string;
	prompt_on_shell?: boolean;
};

type AwsRolesAnywhereData = {
	enable?: boolean;
	region?: string;
	account_id?: string;
	role_name?: string;
	trust_anchor_arn?: string;
	profile_arn?: string;
	cache_buffer_seconds?: string;
	prompt_on_shell?: boolean;
};

type AwsData = {
	roles_anywhere?: AwsRolesAnywhereData;
};

type ThemeData = {
	enable?: boolean;
	preset?: "stackpanel" | "starship-default";
	config_file?: string | null;
};

type IdeData = {
	enable?: boolean;
	vscode?: {
		enable?: boolean;
	};
};

type UsersSettingsData = {
	disable_github_sync?: boolean;
};

type SecretsData = {
	enable?: boolean;
};

type BinaryCacheData = {
	enable?: boolean;
	cachix?: {
		enable?: boolean;
		cache?: string;
		token_path?: string;
	};
};

const starshipPresets = [
	{ value: "stackpanel", label: "Stackpanel (Custom)" },
	{ value: "starship-default", label: "Starship Default" },
];

const optionalValue = (value: string) => {
	const trimmed = value.trim();
	return trimmed.length > 0 ? trimmed : undefined;
};

export function ConfigurationPanel() {
	const { data: config } = useNixConfig();
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

	const [githubRepo, setGithubRepo] = useState("");
	const [githubSyncEnabled, setGithubSyncEnabled] = useState(true);
	const [savingGithub, setSavingGithub] = useState(false);

	const [stepEnabled, setStepEnabled] = useState(false);
	const [stepCaUrl, setStepCaUrl] = useState("");
	const [stepCaFingerprint, setStepCaFingerprint] = useState("");
	const [stepProvisioner, setStepProvisioner] = useState("");
	const [stepCertName, setStepCertName] = useState("");
	const [stepPromptOnShell, setStepPromptOnShell] = useState(false);
	const [savingStepCa, setSavingStepCa] = useState(false);

	const [awsEnabled, setAwsEnabled] = useState(false);
	const [awsRegion, setAwsRegion] = useState("");
	const [awsAccountId, setAwsAccountId] = useState("");
	const [awsRoleName, setAwsRoleName] = useState("");
	const [awsTrustAnchorArn, setAwsTrustAnchorArn] = useState("");
	const [awsProfileArn, setAwsProfileArn] = useState("");
	const [awsCacheBufferSeconds, setAwsCacheBufferSeconds] = useState("");
	const [awsPromptOnShell, setAwsPromptOnShell] = useState(false);
	const [savingAws, setSavingAws] = useState(false);

	const [themeEnabled, setThemeEnabled] = useState(false);
	const [themePreset, setThemePreset] = useState("stackpanel");
	const [savingTheme, setSavingTheme] = useState(false);

	const [ideEnabled, setIdeEnabled] = useState(false);
	const [vscodeEnabled, setVscodeEnabled] = useState(false);
	const [savingIde, setSavingIde] = useState(false);

	const [cacheEnabled, setCacheEnabled] = useState(false);
	const [cachixEnabled, setCachixEnabled] = useState(false);
	const [cachixCache, setCachixCache] = useState("");
	const [cachixTokenPath, setCachixTokenPath] = useState("");
	const [savingCache, setSavingCache] = useState(false);

	const secretsEnabled = secretsData?.enable ?? secretsConfig?.enable ?? false;

	useEffect(() => {
		const repoValue = githubData ?? githubConfig ?? "";
		setGithubRepo(repoValue);
		setGithubSyncEnabled(!(usersSettingsData?.disable_github_sync ?? false));
	}, [githubData, githubConfig, usersSettingsData?.disable_github_sync]);

	useEffect(() => {
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
	}, [stepCaData, stepConfig]);

	useEffect(() => {
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
	}, [awsData, awsConfig]);

	useEffect(() => {
		setThemeEnabled(themeData?.enable ?? themeConfig?.enable ?? false);
		setThemePreset(themeData?.preset ?? themeConfig?.preset ?? "stackpanel");
	}, [themeData, themeConfig]);

	useEffect(() => {
		setIdeEnabled(ideData?.enable ?? ideConfig?.enable ?? false);
		setVscodeEnabled(
			ideData?.vscode?.enable ?? ideConfig?.vscode?.enable ?? false,
		);
	}, [ideData, ideConfig]);

	useEffect(() => {
		setCacheEnabled(cacheData?.enable ?? false);
		setCachixEnabled(cacheData?.cachix?.enable ?? false);
		setCachixCache(cacheData?.cachix?.cache ?? "");
		setCachixTokenPath(cacheData?.cachix?.token_path ?? "");
	}, [cacheData]);

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

	const cachixControlsDisabled = !cacheEnabled || !secretsEnabled;

	return (
		<div className="">
			<div className="pb-4">
				<h2 className="font-semibold text-foreground text-xl">Configuration</h2>
				<p className="text-muted-foreground text-sm">
					Manage Stackpanel settings that don’t need their own page
				</p>
			</div>

			<div className="grid xl:grid-cols-2 gap-6">
				<Card className={githubRepo.trim() ? "" : "opacity-95"}>
					<CardHeader>
						<CardTitle className="flex items-center gap-2">
							<Github className="h-5 w-5 text-accent" />
							GitHub
						</CardTitle>
					</CardHeader>
					<CardContent className="space-y-4">
						<div className="grid gap-2">
							<Label htmlFor="github-repo">Repository</Label>
							<Input
								id="github-repo"
								placeholder="owner/repo"
								value={githubRepo}
								onChange={(event) => setGithubRepo(event.target.value)}
							/>
						</div>
						<div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
							<div>
								<p className="font-medium text-sm">GitHub user sync</p>
								<p className="text-muted-foreground text-xs">
									Sync collaborators and public keys from the repository
								</p>
							</div>
							<Switch
								className="data-[state=checked]:bg-accent"
								checked={githubSyncEnabled}
								onCheckedChange={setGithubSyncEnabled}
							/>
						</div>
						<div className="flex justify-end">
							<Button onClick={saveGithub} disabled={savingGithub}>
								{savingGithub ? "Saving..." : "Save"}
							</Button>
						</div>
					</CardContent>
				</Card>

				<Card className={stepEnabled ? "" : "opacity-95"}>
					<CardHeader>
						<CardTitle className="flex items-center gap-2">
							<Shield className="h-5 w-5 text-accent" />
							Step CA
						</CardTitle>
					</CardHeader>
					<CardContent className="space-y-4">
						<div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
							<div>
								<p className="font-medium text-sm">Enable Step CA</p>
								<p className="text-muted-foreground text-xs">
									Issue local TLS certificates for your team
								</p>
							</div>
							<Switch checked={stepEnabled} onCheckedChange={setStepEnabled} />
						</div>
						<div className="grid gap-4 sm:grid-cols-2">
							<div className="grid gap-2">
								<Label htmlFor="step-ca-url">CA URL</Label>
								<Input
									id="step-ca-url"
									placeholder="https://ca.internal:443"
									value={stepCaUrl}
									onChange={(event) => setStepCaUrl(event.target.value)}
								/>
							</div>
							<div className="grid gap-2">
								<Label htmlFor="step-ca-fingerprint">CA Fingerprint</Label>
								<Input
									id="step-ca-fingerprint"
									placeholder="SHA256 fingerprint"
									value={stepCaFingerprint}
									onChange={(event) => setStepCaFingerprint(event.target.value)}
								/>
							</div>
							<div className="grid gap-2">
								<Label htmlFor="step-ca-provisioner">Provisioner</Label>
								<Input
									id="step-ca-provisioner"
									placeholder="Provisioner name"
									value={stepProvisioner}
									onChange={(event) => setStepProvisioner(event.target.value)}
								/>
							</div>
							<div className="grid gap-2">
								<Label htmlFor="step-ca-cert">Certificate Name</Label>
								<Input
									id="step-ca-cert"
									placeholder="device"
									value={stepCertName}
									onChange={(event) => setStepCertName(event.target.value)}
								/>
							</div>
						</div>
						<div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
							<div>
								<p className="font-medium text-sm">Prompt on shell entry</p>
								<p className="text-muted-foreground text-xs">
									Remind users to set up certificates if missing
								</p>
							</div>
							<Switch
								checked={stepPromptOnShell}
								onCheckedChange={setStepPromptOnShell}
							/>
						</div>
						<div className="flex justify-end">
							<Button onClick={saveStepCa} disabled={savingStepCa}>
								{savingStepCa ? "Saving..." : "Save"}
							</Button>
						</div>
					</CardContent>
				</Card>

				<Card className={awsEnabled ? "" : "opacity-95"}>
					<CardHeader>
						<CardTitle className="flex items-center gap-2">
							<Lock className="h-5 w-5 text-accent" />
							AWS Roles Anywhere
						</CardTitle>
					</CardHeader>
					<CardContent className="space-y-4">
						<div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
							<div>
								<p className="font-medium text-sm">Enable AWS auth</p>
								<p className="text-muted-foreground text-xs">
									Use cert-based authentication for AWS
								</p>
							</div>
							<Switch checked={awsEnabled} onCheckedChange={setAwsEnabled} />
						</div>
						<div className="grid gap-4 sm:grid-cols-2">
							<div className="grid gap-2">
								<Label htmlFor="aws-region">Region</Label>
								<Input
									id="aws-region"
									placeholder="us-west-2"
									value={awsRegion}
									onChange={(event) => setAwsRegion(event.target.value)}
								/>
							</div>
							<div className="grid gap-2">
								<Label htmlFor="aws-account">Account ID</Label>
								<Input
									id="aws-account"
									placeholder="123456789"
									value={awsAccountId}
									onChange={(event) => setAwsAccountId(event.target.value)}
								/>
							</div>
							<div className="grid gap-2">
								<Label htmlFor="aws-role">Role name</Label>
								<Input
									id="aws-role"
									placeholder="developer"
									value={awsRoleName}
									onChange={(event) => setAwsRoleName(event.target.value)}
								/>
							</div>
							<div className="grid gap-2">
								<Label htmlFor="aws-cache-buffer">Cache buffer (seconds)</Label>
								<Input
									id="aws-cache-buffer"
									placeholder="300"
									value={awsCacheBufferSeconds}
									onChange={(event) =>
										setAwsCacheBufferSeconds(event.target.value)
									}
								/>
							</div>
							<div className="grid gap-2 sm:col-span-2">
								<Label htmlFor="aws-trust-anchor">Trust anchor ARN</Label>
								<Input
									id="aws-trust-anchor"
									placeholder="arn:aws:rolesanywhere:..."
									value={awsTrustAnchorArn}
									onChange={(event) => setAwsTrustAnchorArn(event.target.value)}
								/>
							</div>
							<div className="grid gap-2 sm:col-span-2">
								<Label htmlFor="aws-profile-arn">Profile ARN</Label>
								<Input
									id="aws-profile-arn"
									placeholder="arn:aws:rolesanywhere:..."
									value={awsProfileArn}
									onChange={(event) => setAwsProfileArn(event.target.value)}
								/>
							</div>
						</div>
						<div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
							<div>
								<p className="font-medium text-sm">Prompt on shell entry</p>
								<p className="text-muted-foreground text-xs">
									Ask users to finish AWS auth if missing
								</p>
							</div>
							<Switch
								checked={awsPromptOnShell}
								onCheckedChange={setAwsPromptOnShell}
							/>
						</div>
						<div className="flex justify-end">
							<Button onClick={saveAws} disabled={savingAws}>
								{savingAws ? "Saving..." : "Save"}
							</Button>
						</div>
					</CardContent>
				</Card>

				<Card className={themeEnabled ? "" : "opacity-95"}>
					<CardHeader>
						<CardTitle className="flex items-center gap-2">
							<Terminal className="h-5 w-5 text-accent" />
							Starship Prompt
						</CardTitle>
					</CardHeader>
					<CardContent className="space-y-4">
						<div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
							<div>
								<p className="font-medium text-sm">Enable prompt theme</p>
								<p className="text-muted-foreground text-xs">
									Apply the shared Starship theme for your shell
								</p>
							</div>
							<Switch
								checked={themeEnabled}
								onCheckedChange={setThemeEnabled}
							/>
						</div>
						<div className="grid gap-2">
							<Label>Preset</Label>
							<Select value={themePreset} onValueChange={setThemePreset}>
								<SelectTrigger>
									<SelectValue placeholder="Choose a preset" />
								</SelectTrigger>
								<SelectContent>
									{starshipPresets.map((preset) => (
										<SelectItem key={preset.value} value={preset.value}>
											{preset.label}
										</SelectItem>
									))}
								</SelectContent>
							</Select>
						</div>
						<div className="flex justify-end">
							<Button onClick={saveTheme} disabled={savingTheme}>
								{savingTheme ? "Saving..." : "Save"}
							</Button>
						</div>
					</CardContent>
				</Card>

				<Card className={ideEnabled ? "" : "opacity-95"}>
					<CardHeader>
						<CardTitle className="flex items-center gap-2">
							<Settings className="h-5 w-5 text-accent" />
							VS Code Integration
						</CardTitle>
					</CardHeader>
					<CardContent className="space-y-4">
						<div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
							<div>
								<p className="font-medium text-sm">Enable IDE integration</p>
								<p className="text-muted-foreground text-xs">
									Generate workspace files and settings for the team
								</p>
							</div>
							<Switch checked={ideEnabled} onCheckedChange={setIdeEnabled} />
						</div>
						<div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
							<div>
								<p className="font-medium text-sm">VS Code workspace</p>
								<p className="text-muted-foreground text-xs">
									Include VS Code settings in generated files
								</p>
							</div>
							<Switch
								checked={vscodeEnabled}
								onCheckedChange={setVscodeEnabled}
							/>
						</div>
						<div className="flex justify-end">
							<Button onClick={saveIde} disabled={savingIde}>
								{savingIde ? "Saving..." : "Save"}
							</Button>
						</div>
					</CardContent>
				</Card>

				<Card className={cacheEnabled ? "" : "opacity-95"}>
					<CardHeader>
						<CardTitle className="flex items-center gap-2">
							<Shield className="h-5 w-5 text-accent" />
							Binary Cache (Cachix)
						</CardTitle>
					</CardHeader>
					<CardContent className="space-y-4">
						{!secretsEnabled && (
							<div className="flex items-start gap-2 rounded-lg border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-600 dark:text-amber-400">
								<AlertTriangle className="mt-0.5 h-4 w-4" />
								<p>
									Secrets must be enabled before configuring Cachix push tokens.
								</p>
							</div>
						)}
						<div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
							<div>
								<p className="font-medium text-sm">Enable binary cache</p>
								<p className="text-muted-foreground text-xs">
									Use Cachix to speed up local builds
								</p>
							</div>
							<Switch
								checked={cacheEnabled}
								onCheckedChange={setCacheEnabled}
							/>
						</div>
						<div className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
							<div>
								<p className="font-medium text-sm">Push to Cachix</p>
								<p className="text-muted-foreground text-xs">
									Upload build artifacts to a shared cache
								</p>
							</div>
							<Switch
								checked={cachixEnabled}
								onCheckedChange={setCachixEnabled}
								disabled={!cacheEnabled || !secretsEnabled}
							/>
						</div>
						<div className="grid gap-4 sm:grid-cols-2">
							<div className="grid gap-2">
								<Label htmlFor="cachix-cache">Cachix cache name</Label>
								<Input
									id="cachix-cache"
									placeholder="my-cache"
									value={cachixCache}
									onChange={(event) => setCachixCache(event.target.value)}
									disabled={!cacheEnabled}
								/>
							</div>
							<div className="grid gap-2">
								<Label htmlFor="cachix-token">Cachix token path</Label>
								<Input
									id="cachix-token"
									placeholder=".stackpanel/secrets/cachix.token"
									value={cachixTokenPath}
									onChange={(event) => setCachixTokenPath(event.target.value)}
									disabled={cachixControlsDisabled}
								/>
							</div>
						</div>
						<div className="flex justify-between text-xs text-muted-foreground">
							<div className="flex items-center gap-2">
								<Badge variant="secondary">Secrets</Badge>
								<span>{secretsEnabled ? "Enabled" : "Disabled"}</span>
							</div>
							<div className="flex items-center gap-2">
								{cacheEnabled && cachixEnabled ? (
									<Check className="h-4 w-4 text-green-500" />
								) : null}
								<span>
									{cachixControlsDisabled
										? "Enable secrets and cache to push"
										: "Ready for Cachix push"}
								</span>
							</div>
						</div>
						<div className="flex justify-end">
							<Button onClick={saveCache} disabled={savingCache}>
								{savingCache ? "Saving..." : "Save"}
							</Button>
						</div>
					</CardContent>
				</Card>
			</div>
		</div>
	);
}
