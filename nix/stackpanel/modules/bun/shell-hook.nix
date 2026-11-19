# Workspace setup for bundled Bun apps; no JS language pack required.
{
  pkgs,
  lib,
  bunPkg,
  workspaceDir,
  install,
}:
let
  textLockfile = lib.versionAtLeast bunPkg.version "1.2";
  lockfile = if textLockfile then "bun.lock" else "yarn.lock";
  flags = [
    (if textLockfile then "--save-text-lockfile" else "--yarn")
  ]
  ++ lib.optional install.offline "--offline";
  dir =
    if lib.hasPrefix "/" workspaceDir then
      lib.escapeShellArg workspaceDir
    else
      ''"''${STACKPANEL_ROOT:-$PWD}"/${lib.escapeShellArg workspaceDir}'';
  installWorkspace = pkgs.writeShellScript "stackpanel-bun-install" ''
    set -eu
    cd -- "$1"
    if [[ ! -f package.json ]]; then
      echo "No package.json in $PWD; run 'bun init' to create one." >&2
      exit 0
    fi

    stamp=node_modules/${lockfile}.checksum
    fingerprint() {
      local digest
      digest=$(${pkgs.coreutils}/bin/sha256sum ${lockfile}) || return 1
      printf '%s:%s\n' ${lib.escapeShellArg bunPkg.version} "''${digest%% *}"
    }
    if [[ -f ${lockfile} && -s $stamp ]]; then
      current=$(fingerprint)
      if [[ $current == "$(<"$stamp")" ]]; then exit 0; fi
    fi

    if ! ${bunPkg}/bin/bun install ${lib.escapeShellArgs flags}; then
      echo "Bun install failed in $PWD; no install recorded. Run 'bun install' to retry." >&2
      exit 1
    fi
    # The first install may have created or updated the lockfile. Stamp only
    # the successful result so an offline/cache failure is retried next entry.
    if [[ -f ${lockfile} ]]; then
      mkdir -p node_modules
      fingerprint > "$stamp"
    fi
  '';
in
''
  _stackpanel_bun_dir=${dir}
  export PATH="$_stackpanel_bun_dir/node_modules/.bin:$PATH"
  ${lib.optionalString install.enable ''${installWorkspace} "$_stackpanel_bun_dir" || return $?''}
  unset _stackpanel_bun_dir
''
