/**
 * Type definitions for the configuration panel.
 */

export type StepCaData = {
	enable?: boolean;
	ca_url?: string;
	ca_fingerprint?: string;
	cert_name?: string;
	provisioner?: string;
	prompt_on_shell?: boolean;
};

export type AwsRolesAnywhereData = {
	enable?: boolean;
	region?: string;
	account_id?: string;
	role_name?: string;
	trust_anchor_arn?: string;
	profile_arn?: string;
	cache_buffer_seconds?: string;
	prompt_on_shell?: boolean;
};

export type AwsData = {
	roles_anywhere?: AwsRolesAnywhereData;
};

export type ThemeData = {
	enable?: boolean;
	preset?: "stackpanel" | "starship-default";
	config_file?: string | null;
};

export type IdeData = {
	enable?: boolean;
	vscode?: {
		enable?: boolean;
	};
};

export type UsersSettingsData = {
	disable_github_sync?: boolean;
};

export type SecretsData = {
	enable?: boolean;
};

export type BinaryCacheData = {
	enable?: boolean;
	cachix?: {
		enable?: boolean;
		cache?: string;
		token_path?: string;
	};
};
