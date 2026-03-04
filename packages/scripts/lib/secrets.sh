#!/usr/bin/env bash
# ==============================================================================
# secrets.sh - Secret loading for stackpanel entrypoints
#
# This library provides functions to load secrets using whatever backend
# is configured in stackpanel:
#   - secrets:env script (if in devshell)
#   - Direct age decryption (if master keys available)
#   - Vals for external stores (SSM, Vault, etc.)
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
#   load_secrets "web" "dev"
# ==============================================================================

# ==============================================================================
# Main Secret Loading Function
# ==============================================================================

# Load secrets for an app/environment
# Delegates to the stackpanel secrets infrastructure
#
# Usage: load_secrets <app_name> <environment>
# Example: load_secrets "web" "dev"
load_secrets() {
	local app="${1:-}"
	local environment="${2:-dev}"
	local secrets_dir="${STACKPANEL_SECRETS_DIR:-.stack/secrets}"
	local backend="${STACKPANEL_VARIABLES_BACKEND:-vals}"

	log_debug "Loading secrets for app='$app' env='$environment' backend='$backend'"

	# If backend is chamber, use chamber exec to load secrets as env vars
	if [[ "$backend" == "chamber" ]]; then
		if _load_chamber_secrets "$environment"; then
			return 0
		fi
		log_error "Chamber secret loading failed"
		return 1
	fi

	# --- vals backend (default) ---

	# Option 1: Use existing stackpanel secrets:env script if available
	if command_exists "secrets:env"; then
		log_debug "Loading secrets via secrets:env"
		local secrets_output
		if secrets_output=$(secrets:env --app "$app" --env "$environment" 2>/dev/null); then
			eval "$secrets_output"
			log_info "Secrets loaded via secrets:env"
			return 0
		fi
		log_debug "secrets:env failed, trying other methods"
	fi

	# Option 2: Direct age decryption with master keys
	local master_keys_json="${STACKPANEL_MASTER_KEYS:-}"
	if [[ -n "$master_keys_json" ]]; then
		log_debug "Loading secrets via age decryption"
		if _load_age_secrets "$secrets_dir" "$master_keys_json"; then
			log_info "Secrets loaded via age decryption"
			return 0
		fi
		log_debug "Age decryption failed, trying other methods"
	fi

	# Option 3: Vals for external stores (SSM, Vault, etc.)
	local secrets_template="$secrets_dir/$environment.yaml"
	if [[ -f "$secrets_template" ]] && command_exists vals; then
		log_debug "Loading secrets via vals from $secrets_template"
		if _load_vals_secrets "$secrets_template"; then
			log_info "Secrets loaded via vals"
			return 0
		fi
		log_debug "Vals loading failed"
	fi

	# Option 4: Check for environment-specific secrets file
	local env_secrets_file="$secrets_dir/vars/$environment.env"
	if [[ -f "$env_secrets_file" ]]; then
		log_debug "Loading secrets from $env_secrets_file"
		# shellcheck disable=SC1090
		source "$env_secrets_file"
		log_info "Secrets loaded from env file"
		return 0
	fi

	log_warn "No secrets backend available - continuing without secrets"
	return 0
}

# ==============================================================================
# Age Decryption (for dev environments)
# ==============================================================================

# Load secrets by decrypting .age files with master keys
# Usage: _load_age_secrets <secrets_dir> <master_keys_json>
_load_age_secrets() {
	local secrets_dir="$1"
	local master_keys_json="$2"
	local vars_dir="$secrets_dir/vars"
	local loaded_count=0

	if [[ ! -d "$vars_dir" ]]; then
		log_debug "Secrets vars directory not found: $vars_dir"
		return 1
	fi

	if ! command_exists age; then
		log_debug "age command not found"
		return 1
	fi

	for age_file in "$vars_dir"/*.age; do
		[[ -f "$age_file" ]] || continue

		local key_name
		key_name=$(basename "$age_file" .age)

		local value
		if value=$(_try_decrypt_with_master_keys "$age_file" "$master_keys_json" 2>/dev/null); then
			export "$key_name=$value"
			log_debug "Loaded secret: $key_name"
			((loaded_count++))
		else
			log_debug "Failed to decrypt: $key_file"
		fi
	done

	if [[ $loaded_count -gt 0 ]]; then
		log_debug "Loaded $loaded_count secrets via age"
		return 0
	fi

	return 1
}

# Try to decrypt a file using available master keys
# Usage: _try_decrypt_with_master_keys <file> <master_keys_json>
_try_decrypt_with_master_keys() {
	local age_file="$1"
	local master_keys_json="$2"

	# Parse master keys and try each one
	local key_names
	key_names=$(echo "$master_keys_json" | jq -r 'keys[]' 2>/dev/null) || return 1

	for key_name in $key_names; do
		local ref resolve_cmd private_key
		ref=$(echo "$master_keys_json" | jq -r --arg k "$key_name" '.[$k].ref // ""')
		resolve_cmd=$(echo "$master_keys_json" | jq -r --arg k "$key_name" '.[$k]["resolve-cmd"] // ""')

		# Resolve the private key
		private_key=$(_resolve_master_key "$key_name" "$ref" "$resolve_cmd" 2>/dev/null) || continue

		if [[ -n "$private_key" ]]; then
			# Try to decrypt with this key
			local decrypted
			if decrypted=$(echo "$private_key" | age -d -i - "$age_file" 2>/dev/null); then
				echo "$decrypted"
				return 0
			fi
		fi
	done

	return 1
}

# Resolve a master key from its reference
# Usage: _resolve_master_key <name> <ref> <resolve_cmd>
_resolve_master_key() {
	local name="$1"
	local ref="$2"
	local resolve_cmd="$3"

	# If custom resolve command is provided, use it
	if [[ -n "$resolve_cmd" ]]; then
		eval "$resolve_cmd"
		return $?
	fi

	# If ref is a file path, read it
	if [[ "$ref" == ref+file://* ]]; then
		local file_path="${ref#ref+file://}"
		if [[ -f "$file_path" ]]; then
			cat "$file_path"
			return 0
		fi
	fi

	# Use vals if available and ref looks like a vals reference
	if [[ "$ref" == ref+* ]] && command_exists vals; then
		vals eval -e "key: $ref" 2>/dev/null | grep -oP '(?<=key: ).*'
		return $?
	fi

	return 1
}

# ==============================================================================
# Chamber Loading (AWS SSM Parameter Store)
# ==============================================================================

# Load secrets using chamber (AWS SSM Parameter Store)
# The chamber service path is: {STACKPANEL_CHAMBER_SERVICE_PREFIX}/{env}
# Usage: _load_chamber_secrets <environment>
_load_chamber_secrets() {
	local environment="$1"
	local service_prefix="${STACKPANEL_CHAMBER_SERVICE_PREFIX:-}"

	if [[ -z "$service_prefix" ]]; then
		log_error "STACKPANEL_CHAMBER_SERVICE_PREFIX is not set"
		return 1
	fi

	if ! command_exists chamber; then
		log_error "chamber not found - required for chamber backend"
		log_error "Install: https://github.com/segmentio/chamber"
		return 1
	fi

	local service="${service_prefix}/${environment}"
	log_debug "Loading secrets via chamber from service '$service'"

	# Use chamber exec with env to export all secrets as environment variables
	# We use `chamber env` to get KEY=VALUE pairs and eval them
	local chamber_output
	if chamber_output=$(chamber env "$service" 2>/dev/null); then
		# chamber env outputs KEY=VALUE pairs, one per line
		while IFS= read -r line; do
			[[ -z "$line" ]] && continue
			export "$line"
			local key="${line%%=*}"
			log_debug "Loaded secret: $key"
		done <<<"$chamber_output"
		log_info "Secrets loaded via chamber (service: $service)"
		return 0
	fi

	log_error "Failed to load secrets via chamber (service: $service)"
	log_error "Ensure AWS credentials are configured and the service exists in SSM Parameter Store"
	return 1
}

# ==============================================================================
# Vals Loading (for external secret stores)
# ==============================================================================

# Load secrets using vals (supports SSM, Secrets Manager, Vault, etc.)
# Usage: _load_vals_secrets <template_file>
_load_vals_secrets() {
	local template_file="$1"

	if ! command_exists vals; then
		log_error "vals not found - required for external secret stores"
		log_error "Install: curl -L https://github.com/helmfile/vals/releases/latest/download/vals_linux_amd64.tar.gz | tar xz"
		return 1
	fi

	if [[ ! -f "$template_file" ]]; then
		log_error "Secrets template not found: $template_file"
		return 1
	fi

	log_debug "Resolving secrets via vals from $template_file"

	# vals eval outputs YAML, convert to env exports
	local vals_output
	if vals_output=$(vals eval -f "$template_file" 2>/dev/null); then
		# Parse YAML output and export as env vars
		while IFS=': ' read -r key value; do
			# Skip empty lines and comments
			[[ -z "$key" ]] && continue
			[[ "$key" == \#* ]] && continue

			# Remove quotes from value if present
			value="${value#\"}"
			value="${value%\"}"
			value="${value#\'}"
			value="${value%\'}"

			export "$key=$value"
			log_debug "Loaded secret: $key"
		done <<<"$vals_output"

		return 0
	fi

	log_error "Failed to load secrets via vals - check permissions and secret paths"
	return 1
}
