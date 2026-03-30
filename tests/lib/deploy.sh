#!/usr/bin/env bash
# ==============================================================================
# tests/lib/deploy.sh — stackpanel and Alchemy deployment helpers
#
# Requires: tests/lib/common.sh must be sourced first (provides log, ok, info,
#           die, REPO_ROOT).
# sops.sh must be sourced first when using run_alchemy_deploy.
#
# Functions:
#   run_stackpanel_provision <machine_name> <install_target> <mode> [flags...]
#   run_stackpanel_deploy    <app_name> <dry_run:true|false>
#   run_alchemy_deploy       <stage> <secrets_file> <entrypoint>
# ==============================================================================

# run_stackpanel_provision <machine_name> <install_target> <mode> [extra_flags...]
#
# Runs `stackpanel provision` from REPO_ROOT.
# <mode>: "dry-run"  → adds --dry-run (config + command plan only; no nixos-anywhere)
#         "full"     → no --dry-run flag (full provision including nixos-anywhere)
# --no-hardware-config is always added to skip the SSH hardware-detection step.
# Any additional <extra_flags> are appended after the standard flags.
run_stackpanel_provision() {
  local machine_name="$1"
  local install_target="$2"
  local mode="${3:-dry-run}"
  shift 3
  # Remaining positional args become extra flags (may be empty)
  local -a extra_flags=("$@")

  local -a flags=()
  if [[ "${mode}" == "dry-run" ]]; then
    flags+=("--dry-run")
    info "Mode: dry-run (config + command plan validated; nixos-anywhere NOT invoked)"
    info "Use full mode to run the complete provision including nixos-anywhere."
  fi
  # --no-hardware-config avoids the SSH hardware-detection step so dry-run
  # exercises the full command path without an extra SSH round-trip.
  flags+=("--no-hardware-config")
  [[ ${#extra_flags[@]} -gt 0 ]] && flags+=("${extra_flags[@]}")

  log "Running stackpanel provision ${machine_name} --install-target ${install_target}..."
  (
    cd "${REPO_ROOT}"
    stackpanel provision "${machine_name}" \
      --install-target "${install_target}" \
      "${flags[@]}"
  )
  ok "stackpanel provision completed (${mode} mode)"
}

# run_stackpanel_deploy <app_name> <dry_run>
#
# Runs `stackpanel deploy <app_name>` optionally with --dry-run.
# <dry_run>: "true" (default) → adds --dry-run; "false" → full deploy
run_stackpanel_deploy() {
  local app_name="$1"
  local dry_run="${2:-true}"

  local -a flags=()
  [[ "${dry_run}" == "true" ]] && flags+=("--dry-run")

  log "Running stackpanel deploy ${app_name}${dry_run:+ (dry-run)}..."
  (
    cd "${REPO_ROOT}"
    stackpanel deploy "${app_name}" "${flags[@]+"${flags[@]}"}"
  )
  ok "stackpanel deploy ${app_name} completed"
}

# run_alchemy_deploy <stage> <secrets_file> <entrypoint>
#
# Runs `bun <entrypoint>` with all secrets injected from <secrets_file> via
# `sops exec-env`.
run_alchemy_deploy() {
  local stage="$1"
  local secrets_file="$2"
  local entrypoint="$3"

  local sops_bin
  sops_bin="$(find_sops_bin)" || die "sops not found. Run inside the devshell: nix develop --impure"

  log "Running Alchemy deploy (stage: ${stage}, entrypoint: $(basename "${entrypoint}"))..."
  (
    cd "${REPO_ROOT}"
    "${sops_bin}" exec-env "${secrets_file}" \
      "STAGE=$(printf '%q' "${stage}") bun $(printf '%q' "${entrypoint}")"
  )
  ok "Alchemy deploy completed (stage: ${stage})"
}
