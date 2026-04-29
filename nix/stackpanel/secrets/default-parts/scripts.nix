{
  pkgs,
  lib,
  cfg,
  cfgLib,
  secretsLib,
  masterKeysConfig,
  sopsAgeSources,
  sopsAgeSourceLines,
  sopsAgeKeyPaths,
  sopsAgeKeyOpRefs,
  sopsKeyservices,
  projectRoot,
  recipientsConfig ? {},
}: let
  cfgDir = cfg.secrets-dir;
in rec {
  inherit cfgDir;

  sopsAgeKeys = pkgs.writeShellApplication {
    name = "sops-age-keys";
    text = ''
            ${cfgLib.bashLib}

            LOCAL_KEY_FILE=${cfgLib.getKnown "paths.local-key"}
            PROJECT_ROOT=${lib.escapeShellArg projectRoot}

      SOURCE_LINES="${sopsAgeSourceLines}"
      if [[ -n "''${SOPS_AGE_SOURCE_LINES_OVERRIDE:-}" ]]; then
        SOURCE_LINES="$SOPS_AGE_SOURCE_LINES_OVERRIDE"
      fi
            MODE="private"
            JSON_OUTPUT=0
            FIRST_ONLY=0

            while [[ $# -gt 0 ]]; do
              case "$1" in
                --public)
                  MODE="public"
                  shift
                  ;;
                --private)
                  MODE="private"
                  shift
                  ;;
                --json)
                  JSON_OUTPUT=1
                  shift
                  ;;
                --first)
                  FIRST_ONLY=1
                  shift
                  ;;
                -h|--help)
                  cat <<EOF
      Usage: sops-age-keys [--public|--private] [--first] [--json]

      Default output prints all resolved AGE private keys for use with SOPS_AGE_KEY_CMD.
        --public   Print derived public keys instead of private keys
        --first    Print only the first resolved key
        --json     Print machine-readable JSON with both private/public keys
      EOF
                  exit 0
                  ;;
                *)
                  echo "Unknown option: $1" >&2
                  exit 2
                  ;;
              esac
            done

            resolve_key_file() {
              local candidate="$1"

              [[ -z "$candidate" ]] && return 1

              local expanded="$candidate"
              expanded="''${expanded/#\$HOME/$HOME}"
              expanded="''${expanded/#\~/$HOME}"
              if [[ -n "''${XDG_CONFIG_HOME:-}" ]]; then
                expanded="''${expanded//\$XDG_CONFIG_HOME/''${XDG_CONFIG_HOME}}"
              fi

              if [[ -f "$expanded" ]]; then
                printf '%s\n' "$expanded"
                return 0
              fi

              if [[ "$expanded" != /* ]]; then
                if [[ -n "$PROJECT_ROOT" && -f "$PROJECT_ROOT/$expanded" ]]; then
                  printf '%s\n' "$PROJECT_ROOT/$expanded"
                  return 0
                fi
                if [[ -f "$(pwd)/$expanded" ]]; then
                  printf '%s\n' "$(pwd)/$expanded"
                  return 0
                fi
              fi

              return 1
            }

            extract_keys() {
              local text="$1"
              printf '%s\n' "$text" | grep '^AGE-SECRET-KEY-' || true
            }

            derive_public_key() {
              local private_key="$1"
              local tmp_file
              tmp_file="$(mktemp)"
              chmod 600 "$tmp_file"
              printf '%s\n' "$private_key" > "$tmp_file"
              ${pkgs.age}/bin/age-keygen -y "$tmp_file" 2>/dev/null || true
              rm -f "$tmp_file"
            }

            json_escape() {
              local value="$1"
              value="''${value//\\/\\\\}"
              value="''${value//\"/\\\"}"
              value="''${value//$'\n'/\\n}"
              value="''${value//$'\r'/\\r}"
              value="''${value//$'\t'/\\t}"
              printf '%s' "$value"
            }

            join_json_array() {
              local first=1
              while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                if [[ $first -eq 0 ]]; then
                  printf ','
                fi
                first=0
                printf '"%s"' "$(json_escape "$line")"
              done
            }

            PRIVATE_KEYS=()
            PUBLIC_KEYS=()
            LOOKED_PATHS=()
            LOOKED_OP_REFS=()
            MISSING_OP=0

            while IFS=$'\t' read -r source_type source_value source_account; do
              [[ -z "$source_type" || -z "$source_value" ]] && continue

              case "$source_type" in
                user-key-path|repo-key-path|file)
                  LOOKED_PATHS+=("$source_value")
                  resolved_path="$(resolve_key_file "$source_value" || true)"
                  if [[ -n "$resolved_path" ]]; then
                    while IFS= read -r key; do
                      [[ -z "$key" ]] && continue
                      PRIVATE_KEYS+=("$key")
                    done < <(extract_keys "$(cat "$resolved_path")")
                  fi
                  ;;
                ssh-key)
                  resolved_path="$(resolve_key_file "$source_value" || true)"
                  if [[ -n "$resolved_path" ]]; then
                    if ! command -v ${pkgs.ssh-to-age}/bin/ssh-to-age >/dev/null 2>&1; then
                      echo "ssh-to-age not available; cannot convert SSH key at $source_value" >&2
                    else
                      while IFS= read -r key; do
                        [[ -z "$key" ]] && continue
                        PRIVATE_KEYS+=("$key")
                      done < <(extract_keys "$(${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i "$resolved_path" 2>/dev/null || true)")
                    fi
                  fi
                  ;;
                keychain)
                  if command -v security >/dev/null 2>&1; then
                    while IFS= read -r key; do
                      [[ -z "$key" ]] && continue
                      PRIVATE_KEYS+=("$key")
                    done < <(extract_keys "$(security find-generic-password -s "$source_value" -a "$source_account" -w 2>/dev/null || true)")
                  fi
                  ;;
                op-ref)
                  LOOKED_OP_REFS+=("$source_value")
                  if ! command -v op >/dev/null 2>&1; then
                    MISSING_OP=1
                    continue
                  fi
                  op_args=()
                  if [[ -n "$source_account" ]]; then
                    op_args+=(--account "$source_account")
                  fi
                  while IFS= read -r key; do
                    [[ -z "$key" ]] && continue
                    PRIVATE_KEYS+=("$key")
                  done < <(
                    op_output="$(op read "''${op_args[@]}" "$source_value" 2>/dev/null || true)"
                    extract_keys "$op_output"
                  )
                  ;;
                vals)
                  while IFS= read -r key; do
                    [[ -z "$key" ]] && continue
                    PRIVATE_KEYS+=("$key")
                  done < <(extract_keys "$(${pkgs.vals}/bin/vals eval -e "$source_value" 2>/dev/null || true)")
                  ;;
                keyservice)
                  ;;
                aws-kms)
                  # value is an AWS SSM parameter path or Secrets Manager ARN
                  # containing an AGE private key (AGE-SECRET-KEY-...) as the value.
                  # Uses current AWS credentials / profile from environment.
                  AWS_STDOUT=""
                  if [[ "$source_value" =~ ^arn:aws:secretsmanager: ]]; then
                    AWS_STDOUT="$(${pkgs.awscli2}/bin/aws secretsmanager get-secret-value \
                      --secret-id "$source_value" \
                      --query SecretString \
                      --output text 2>/dev/null || true)"
                  else
                    AWS_STDOUT="$(${pkgs.awscli2}/bin/aws ssm get-parameter \
                      --name "$source_value" \
                      --with-decryption \
                      --query Parameter.Value \
                      --output text 2>/dev/null || true)"
                  fi
                  while IFS= read -r key; do
                    [[ -z "$key" ]] && continue
                    PRIVATE_KEYS+=("$key")
                  done < <(extract_keys "$AWS_STDOUT")
                  ;;
                script)
                  while IFS= read -r key; do
                    [[ -z "$key" ]] && continue
                    PRIVATE_KEYS+=("$key")
                  done < <(extract_keys "$(bash -lc "$source_value" 2>/dev/null || true)")
                  ;;
              esac
            done <<< "$SOURCE_LINES"

            if [[ ''${#PRIVATE_KEYS[@]} -gt 0 ]]; then
              declare -A seen_public=()
              for private_key in "''${PRIVATE_KEYS[@]}"; do
                public_key="$(derive_public_key "$private_key")"
                if [[ -n "$public_key" && -z "''${seen_public[$public_key]:-}" ]]; then
                  seen_public[$public_key]=1
                  PUBLIC_KEYS+=("$public_key")
                fi
              done
            fi

            if [[ $JSON_OUTPUT -eq 1 ]]; then
              printf '{"available":%s,"privateKeys":[' "$(if [[ ''${#PRIVATE_KEYS[@]} -gt 0 ]]; then printf true; else printf false; fi)"
              printf '%s\n' "''${PRIVATE_KEYS[@]}" | join_json_array
              printf '],"publicKeys":['
              printf '%s\n' "''${PUBLIC_KEYS[@]}" | join_json_array
              printf '],"paths":['
              printf '%s\n' "''${LOOKED_PATHS[@]}" | join_json_array
              printf '],"opRefs":['
              printf '%s\n' "''${LOOKED_OP_REFS[@]}" | join_json_array
              printf '],"missingOp":%s}\n' "$(if [[ $MISSING_OP -eq 1 ]]; then printf true; else printf false; fi)"
              if [[ ''${#PRIVATE_KEYS[@]} -gt 0 ]]; then
                exit 0
              fi
            elif [[ "$MODE" == "public" ]]; then
              if [[ $FIRST_ONLY -eq 1 ]]; then
                [[ ''${#PUBLIC_KEYS[@]} -gt 0 ]] && printf '%s\n' "''${PUBLIC_KEYS[0]}"
              else
                printf '%s\n' "''${PUBLIC_KEYS[@]}"
              fi
              [[ ''${#PUBLIC_KEYS[@]} -gt 0 ]] && exit 0
            else
              if [[ $FIRST_ONLY -eq 1 ]]; then
                [[ ''${#PRIVATE_KEYS[@]} -gt 0 ]] && printf '%s\n' "''${PRIVATE_KEYS[0]}"
              else
                printf '%s\n' "''${PRIVATE_KEYS[@]}"
              fi
              [[ ''${#PRIVATE_KEYS[@]} -gt 0 ]] && exit 0
            fi

            echo "No AGE private key found." >&2
            echo "" >&2

            echo "Looked in these configured sources:" >&2
            while IFS= read -r line; do
              [[ -z "$line" ]] && continue
              echo "  - $line" >&2
            done <<< "$SOURCE_LINES"

            if [[ ''${#LOOKED_OP_REFS[@]} -gt 0 && $MISSING_OP -eq 1 ]]; then
              echo "1Password CLI (op) is not installed. Install and sign in before using those refs." >&2
            fi

            echo "" >&2
            echo "How to fix quickly:" >&2
            cat >&2 <<EOF
        1) Ensure a local key exists: mkdir -p "$(dirname "$LOCAL_KEY_FILE")" && age-keygen -o "$LOCAL_KEY_FILE"
      EOF
            echo "  2) Or add one of the above paths with an AGE-SECRET-KEY-... private key" >&2
            echo "  3) Or configure stackpanel.secrets.sops-age-keys.sources with your preferred ordered sources" >&2
            exit 1

    '';
  };

  rekeyScriptText = ''
    #!/usr/bin/env bash
    set -euo pipefail

    PROJECT_ROOT=${lib.escapeShellArg projectRoot}
    SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")" && pwd)"
    if [[ -d "$PROJECT_ROOT/${cfgDir}/vars" ]]; then
      SECRETS_DIR="$PROJECT_ROOT/${cfgDir}"
    else
      SECRETS_DIR="$(dirname "$SCRIPT_DIR")"
    fi
    VARS_DIR="$SECRETS_DIR/vars"
    # SOPS config lives at repo root so `sops` and editor plugins find it via
    # default discovery. Keep the legacy `$SECRETS_DIR/.sops.yaml` location as a
    # fallback for projects that haven't run preflight after the path migration.
    SOPS_CONFIG="$PROJECT_ROOT/.sops.yaml"
    if [[ ! -f "$SOPS_CONFIG" && -f "$SECRETS_DIR/.sops.yaml" ]]; then
      SOPS_CONFIG="$SECRETS_DIR/.sops.yaml"
    fi
    FILTER="''${1:-}"
    REKEY_COUNT=0

    export SOPS_AGE_KEY_CMD="''${SOPS_AGE_KEY_CMD:-${sopsAgeKeys}/bin/sops-age-keys}"

    if [[ ! -d "$VARS_DIR" ]]; then
      echo "No vars directory found at $VARS_DIR"
      exit 0
    fi

    if [[ ! -f "$SOPS_CONFIG" ]]; then
      echo "Missing SOPS config: $SOPS_CONFIG" >&2
      exit 1
    fi

    shopt -s nullglob
    for file in "$VARS_DIR"/*.sops.yaml; do
      [[ -f "$file" ]] || continue
      group="$(basename "$file" .sops.yaml)"
      if [[ -n "$FILTER" && "$group" != "$FILTER" ]]; then
        continue
      fi

      if ${pkgs.sops}/bin/sops --config "$SOPS_CONFIG" updatekeys --yes "$file" >/dev/null; then
        echo "  $(basename "$file"): updated"
        REKEY_COUNT=$((REKEY_COUNT + 1))
      else
        echo "  $(basename "$file"): FAILED" >&2
        exit 1
      fi
    done

    echo ""
    echo "Updated keys for $REKEY_COUNT secret file(s)"
  '';

  # Wrapped SOPS that uses the generated .sops.yaml plus the current AGE key.
  sopsWrapped = pkgs.writeShellApplication {
    name = "sops";
    text = secretsLib.sopsWrappedScript {
      sopsAgeKeysPath = "${sopsAgeKeys}/bin/sops-age-keys";
    };
  };

  sopsAgeKeychainSave = pkgs.writeShellApplication {
    name = "sops-age-keychain-save";
    runtimeInputs = [
      pkgs.age
      pkgs.ssh-to-age
    ];
    text = ''
            ${cfgLib.bashLib}

            SERVICE=""
            ACCOUNT=""
            FILE_PATH=""
            SSH_FILE=""
            KEYCHAIN_PATH="$HOME/Library/Keychains/login.keychain-db"

            while [[ $# -gt 0 ]]; do
              case "$1" in
                --service)
                  SERVICE="$2"
                  shift 2
                  ;;
                --account)
                  ACCOUNT="$2"
                  shift 2
                  ;;
                --file)
                  FILE_PATH="$2"
                  shift 2
                  ;;
                --ssh)
                  SSH_FILE="$2"
                  shift 2
                  ;;
                --keychain)
                  KEYCHAIN_PATH="$2"
                  shift 2
                  ;;
                -h|--help)
                  cat <<'USAGE'
      Usage: sops-age-keychain-save [OPTIONS]

      Reads AGE private keys and saves each one to the macOS Keychain keyed by its
      derived AGE public key.

      Options:
        --file PATH      Read AGE private keys from file (or stdin if omitted)
        --ssh PATH       Convert SSH private key at PATH to AGE, then save
        --service NAME   Keychain service name (default: repo-scoped)
        --account KEY    Keychain account (default: derived AGE public key)
        --keychain PATH  Keychain file path (default: login.keychain-db)

      USAGE
                  exit 0
                  ;;
                *)
                  echo "Unknown option: $1" >&2
                  exit 2
                  ;;
              esac
            done

            if ! command -v security >/dev/null 2>&1; then
              echo "macOS security CLI not found" >&2
              exit 1
            fi

            if [[ -n "$SSH_FILE" ]]; then
              if [[ ! -f "$SSH_FILE" ]]; then
                echo "SSH private key not found: $SSH_FILE" >&2
                exit 1
              fi
              SSH_CONVERTED="$(ssh-to-age -private-key -i "$SSH_FILE" 2>/dev/null || true)"
              if [[ -z "$SSH_CONVERTED" ]]; then
                echo "Failed to convert SSH key at $SSH_FILE — is it an Ed25519 key?" >&2
                exit 1
              fi
        PRIVATE_KEY_INPUT="$SSH_CONVERTED"
      elif [[ -n "$FILE_PATH" ]]; then
        PRIVATE_KEY_INPUT="$(cat "$FILE_PATH")"
      else
        PRIVATE_KEY_INPUT="$(cat)"
      fi

            default_service() {
              local remote host owner repo base
              base="stackpanel.sops-age-key"
              remote="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || true)"
              if [[ "$remote" == git@*:*/* ]]; then
                host="$(printf '%s' "$remote" | sed -E 's#^git@([^:]+):.*#\1#')"
                owner="$(printf '%s' "$remote" | sed -E 's#^git@[^:]+:([^/]+)/.*#\1#')"
                repo="$(printf '%s' "$remote" | sed -E 's#^git@[^:]+:[^/]+/([^/]+?)(\.git)?$#\1#')"
              elif [[ "$remote" == http*://*/*/* ]]; then
                host="$(printf '%s' "$remote" | sed -E 's#^[a-z]+://([^/]+)/.*#\1#')"
                owner="$(printf '%s' "$remote" | sed -E 's#^[a-z]+://[^/]+/([^/]+)/.*#\1#')"
                repo="$(printf '%s' "$remote" | sed -E 's#^[a-z]+://[^/]+/[^/]+/([^/]+?)(\.git)?$#\1#')"
              elif [[ "$remote" == ssh://git@*/*/* ]]; then
                host="$(printf '%s' "$remote" | sed -E 's#^ssh://git@([^/]+)/.*#\1#')"
                owner="$(printf '%s' "$remote" | sed -E 's#^ssh://git@[^/]+/([^/]+)/.*#\1#')"
                repo="$(printf '%s' "$remote" | sed -E 's#^ssh://git@[^/]+/[^/]+/([^/]+?)(\.git)?$#\1#')"
              else
                repo="$(basename "$PROJECT_ROOT")"
              fi
              sanitize() {
                printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/./g; s/^\.+|\.+$//g; s/\.\.+/./g'
              }
              host="$(sanitize "$host")"
              owner="$(sanitize "$owner")"
              repo="$(sanitize "$repo")"
              printf '%s' "$base"
              [[ -n "$host" ]] && printf '.%s' "$host"
              [[ -n "$owner" ]] && printf '.%s' "$owner"
              [[ -n "$repo" ]] && printf '.%s' "$repo"
            }

            if [[ -z "$SERVICE" ]]; then
              SERVICE="$(default_service)"
            fi

            mapfile -t PRIVATE_KEYS < <(printf '%s\n' "$PRIVATE_KEY_INPUT" | grep '^AGE-SECRET-KEY-' || true)
            if [[ ''${#PRIVATE_KEYS[@]} -eq 0 ]]; then
              echo "No AGE private key found in input" >&2
              exit 1
            fi

            if [[ -n "$ACCOUNT" && ''${#PRIVATE_KEYS[@]} -gt 1 ]]; then
              echo "--account can only be used when saving a single key. Multiple keys default to public-key accounts." >&2
              exit 2
            fi

            saved_any=0
            echo "Saved AGE keys to macOS Keychain"
            echo "  keychain: $KEYCHAIN_PATH"
            echo "  service:  $SERVICE"

            for PRIVATE_KEY in "''${PRIVATE_KEYS[@]}"; do
              TMP_FILE="$(mktemp)"
              chmod 600 "$TMP_FILE"
              printf '%s\n' "$PRIVATE_KEY" > "$TMP_FILE"
              PUBLIC_KEY="$(${pkgs.age}/bin/age-keygen -y "$TMP_FILE")"
              rm -f "$TMP_FILE"

              KEY_ACCOUNT="$ACCOUNT"
              if [[ -z "$KEY_ACCOUNT" ]]; then
                KEY_ACCOUNT="$PUBLIC_KEY"
              fi

              SECURITY_OUTPUT="$(security add-generic-password -U -s "$SERVICE" -a "$KEY_ACCOUNT" -w "$PRIVATE_KEY" "$KEYCHAIN_PATH" 2>&1)"
              SECURITY_EXIT=$?
              if [[ $SECURITY_EXIT -ne 0 ]]; then
                if [[ "$SECURITY_OUTPUT" == *"User interaction is not allowed"* ]]; then
                  echo "Failed to save key: macOS keychain is locked or unavailable to this session." >&2
                  echo "" >&2
                  echo "Try one of these:" >&2
                  echo "  1) Unlock the login keychain in a GUI session" >&2
                  echo "  2) Run: security unlock-keychain \"$KEYCHAIN_PATH\"" >&2
                  echo "  3) Pass a different keychain explicitly with --keychain" >&2
                  echo "" >&2
                  echo "Original error: $SECURITY_OUTPUT" >&2
                  exit 1
                fi
                echo "$SECURITY_OUTPUT" >&2
                exit $SECURITY_EXIT
              fi

              saved_any=1
              echo "  public:  $PUBLIC_KEY"
              echo "  account: $KEY_ACCOUNT"
              echo ""
              echo "Key source config example:"
              printf '%s\n' '{'
              printf '  type = "keychain";\n'
              printf '  value = "%s";\n' "$SERVICE"
              printf '  account = "%s";\n' "$KEY_ACCOUNT"
              printf '%s\n' '  name = "macOS Keychain";'
              printf '%s\n' '}'
              echo ""
            done

            [[ $saved_any -eq 1 ]] || exit 1
    '';
  };

  sopsAgeRecipientsInit = pkgs.writeShellApplication {
    name = "sops-age-recipients-init";
    runtimeInputs = [
      pkgs.age
      pkgs.ssh-to-age
    ];
    text = let
      recipientList =
        lib.mapAttrsToList (name: r: {
          inherit name;
          publicKey = r.public-key or "";
        })
        recipientsConfig;
      recipientJson = builtins.toJSON recipientList;
    in ''
              ${cfgLib.bashLib}

              KEYCHAIN_PATH="$HOME/Library/Keychains/login.keychain-db"
              SERVICE=""
              DRY_RUN=0

              while [[ $# -gt 0 ]]; do
                case "$1" in
                  --dry-run) DRY_RUN=1; shift ;;
                  --service) SERVICE="$2"; shift 2 ;;
                  --keychain) KEYCHAIN_PATH="$2"; shift 2 ;;
                  -h|--help)
                    cat <<'USAGE'
      Usage: sops-age-recipients-init [--dry-run] [--service NAME] [--keychain PATH]

      One-time setup: for every configured recipient whose public key is an SSH key,
      convert it to AGE and ensure the matching private key is stored in the macOS
      Keychain so no runtime conversion is needed.

      The conversion uses sops-age-keys to discover available private keys, derives
      their public keys, and matches them against configured recipients.

      USAGE
                    exit 0 ;;
                  *) echo "Unknown option: $1" >&2; exit 2 ;;
                esac
              done

              if ! command -v security >/dev/null 2>&1; then
                echo "macOS security CLI not found" >&2
                exit 1
              fi

              default_service() {
                local remote base
                base="stackpanel.sops-age-key"
                remote="$(git -C "${projectRoot}" remote get-url origin 2>/dev/null || true)"
                if [[ "$remote" == git@*:*/* ]]; then
                  local host owner repo
          host="$(printf '%s' "$remote" | sed -E 's#^git@([^:]+):.*#\1#' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/./g')"
          owner="$(printf '%s' "$remote" | sed -E 's#^git@[^:]+:([^/]+)/.*#\1#' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/./g')"
          repo="$(printf '%s' "$remote" | sed -E 's#^git@[^:]+:[^/]+/([^/]+?)(\.git)?$#\1#' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/./g')"
                  printf '%s.%s.%s.%s' "$base" "$host" "$owner" "$repo"
                  return
                fi
                printf '%s.%s' "$base" "$(basename "${projectRoot}")"
              }

              if [[ -z "$SERVICE" ]]; then
                SERVICE="$(default_service)"
              fi

              RECIPIENTS='${recipientJson}'

              # Build a map of known private keys -> their derived AGE public keys
              declare -A priv_to_pub=()
              while IFS= read -r line; do
                [[ -z "$line" || ! "$line" =~ ^AGE-SECRET-KEY- ]] && continue
                TMP="$(mktemp)"
                chmod 600 "$TMP"
                printf '%s\n' "$line" > "$TMP"
                pub="$(${pkgs.age}/bin/age-keygen -y "$TMP" 2>/dev/null || true)"
                rm -f "$TMP"
                [[ -n "$pub" ]] && priv_to_pub["$pub"]="$line"
              done < <(${projectRoot}/.stack/bin/sops-age-keys 2>/dev/null || true)

              saved=0
              skipped=0
              missing=0

              while IFS= read -r recipient_name && IFS= read -r public_key; do
                [[ -z "$public_key" ]] && continue

                age_pub=""
                if [[ "$public_key" =~ ^age1 ]]; then
                  age_pub="$public_key"
                elif [[ "$public_key" =~ ^ssh- ]]; then
                  age_pub="$(printf '%s\n' "$public_key" | ssh-to-age 2>/dev/null || true)"
                fi

                if [[ -z "$age_pub" ]]; then
                  echo "  skip $recipient_name: could not derive AGE public key from $public_key" >&2
                  ((skipped++)) || true
                  continue
                fi

                if [[ -z "''${priv_to_pub[$age_pub]+x}" ]]; then
                  echo "  missing $recipient_name ($age_pub): no matching private key in sops-age-keys output" >&2
                  ((missing++)) || true
                  continue
                fi

                priv_key="''${priv_to_pub[$age_pub]}"

                if [[ $DRY_RUN -eq 1 ]]; then
                  echo "  would save $recipient_name -> $age_pub to keychain (service=$SERVICE)"
                  ((saved++)) || true
                  continue
                fi

                SEC_OUT="$(security add-generic-password -U -s "$SERVICE" -a "$age_pub" -w "$priv_key" "$KEYCHAIN_PATH" 2>&1)"
                SEC_EXIT=$?
                if [[ $SEC_EXIT -ne 0 ]]; then
                  if [[ "$SEC_OUT" == *"User interaction is not allowed"* ]]; then
                    echo "Keychain is locked. Run: security unlock-keychain \"$KEYCHAIN_PATH\"" >&2
                    exit 1
                  fi
                  echo "  failed $recipient_name: $SEC_OUT" >&2
                else
                  echo "  saved $recipient_name ($age_pub)"
                  ((saved++)) || true
                fi
              done < <(printf '%s\n' "$RECIPIENTS" | ${pkgs.jq}/bin/jq -r '.[] | (.name, .publicKey)')

              echo ""
              echo "Done: $saved saved, $skipped skipped, $missing missing private keys"
              if [[ $missing -gt 0 ]]; then
                echo ""
                echo "For missing keys: add an SSH Private Key or AGE key source in"
                echo "Variables → SOPS → Key Sources, then run this command again."
              fi
    '';
  };

  secretsSet = pkgs.writeShellApplication {
    name = "secrets-set";
    runtimeInputs = [
      sopsWrapped
      pkgs.gum
      pkgs.yq-go
    ];
    text = secretsLib.setSecretScript;
  };

  secretsGet = pkgs.writeShellApplication {
    name = "secrets-get";
    runtimeInputs = [
      sopsWrapped
      pkgs.gum
      pkgs.yq-go
    ];
    text = secretsLib.getSecretScript;
  };

  secretsList = pkgs.writeShellApplication {
    name = "secrets-list";
    runtimeInputs = [
      sopsWrapped
      pkgs.yq-go
    ];
    text = secretsLib.listSecretsScript;
  };

  secretsRekey = pkgs.writeShellApplication {
    name = "secrets-rekey";
    runtimeInputs = [
      pkgs.age
      pkgs.sops
    ];
    text = rekeyScriptText;
  };

  secretsLoad = pkgs.writeShellApplication {
    name = "secrets-load";
    runtimeInputs = [
      sopsWrapped
    ];
    text = ''
      ${cfgLib.bashLib}

      SECRETS_DIR=${cfgLib.getWithDefault "secrets.secrets-dir" cfgDir}
      VARS_DIR="$SECRETS_DIR/vars"

      usage() {
        echo "Usage: secrets:load <group> [--format dotenv|json|yaml]"
        echo ""
        echo "Decrypt a SOPS vars file and output in the specified format."
        echo ""
        echo "Options:"
        echo "  --format   Output format: dotenv (default), json, yaml"
        echo ""
        echo "Examples:"
        echo "  secrets:load dev"
        echo "  secrets:load common --format json"
        echo "  eval \$(secrets:load dev)   # load into current shell"
        exit 1
      }

      [[ $# -lt 1 ]] && usage

      GROUP="$1"
      shift
      FORMAT="dotenv"

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --format|-f)
            FORMAT="$2"
            shift 2
            ;;
          -h|--help)
            usage
            ;;
          *)
            echo "Unknown option: $1" >&2
            usage
            ;;
        esac
      done

      GROUP_FILE="$VARS_DIR/$GROUP.sops.yaml"

      if [[ ! -f "$GROUP_FILE" ]]; then
        echo "Error: Group file not found: $GROUP_FILE" >&2
        echo "Available groups:" >&2
        for f in "$VARS_DIR"/*.sops.yaml; do
          [[ -f "$f" ]] && echo "  $(basename "$f" .sops.yaml)" >&2
        done
        exit 1
      fi

      case "$FORMAT" in
        dotenv)
          sops decrypt --output-type dotenv "$GROUP_FILE"
          ;;
        json)
          sops decrypt --output-type json "$GROUP_FILE"
          ;;
        yaml)
          sops decrypt "$GROUP_FILE"
          ;;
        *)
          echo "Error: Unknown format: $FORMAT (expected dotenv, json, or yaml)" >&2
          exit 1
          ;;
      esac
    '';
  };
}
