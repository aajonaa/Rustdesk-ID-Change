#!/bin/bash

# ==============================================================================
# RustDesk ID Modifier - V4 (User-Specified Logic - Cleaned)
#
# Process:
# 1. User inputs a PLAIN desired ID (e.g., "sag.ubu").
# 2. Script makes RustDesk generate a NEW enc_id corresponding to this PLAIN ID
#    by temporarily giving RustDesk a minimal config. This will reset salt,
#    key_pair, password etc., in that intermediate, regenerated config.
# 3. Script extracts this NEWLY_GENERATED_ENC_ID.
# 4. IF an ORIGINAL config existed before this script ran, that original config
#    is restored, and THEN ONLY its 'enc_id' line is replaced with the
#    NEWLY_GENERATED_ENC_ID. Other original settings are kept.
# 5. This final modified config file is made immutable.
#
# !! WARNING !! THIS IS HIGHLY EXPERIMENTAL AND RISKY !!
# Forcing a new enc_id while keeping old salt/key_pair from a different
# identity is very likely to create an inconsistent and NON-FUNCTIONAL
# cryptographic state for RustDesk.
# ==============================================================================

# --- Configuration Variables ---
RUSTDESK_CONFIG_FILE="/root/.config/rustdesk/RustDesk.toml"
RUSTDESK_SERVICE_NAME="rustdesk.service"
RUSTDESK_EXECUTABLE="/usr/bin/rustdesk"

# --- Check for Root Privileges ---
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root (e.g., using sudo)." >&2
  exit 1
fi

# --- Helper Functions ---
stop_rustdesk() {
  echo "INFO: Attempting to stop RustDesk service ($RUSTDESK_SERVICE_NAME)..."
  systemctl stop "$RUSTDESK_SERVICE_NAME" &>/dev/null # Try to stop quietly first
  sleep 1
  if systemctl is-active --quiet "$RUSTDESK_SERVICE_NAME"; then
    echo "WARN: Service still active after first stop attempt. Retrying with pkill..."
    pkill --signal SIGTERM -f "$RUSTDESK_EXECUTABLE"
    sleep 2
    pkill --signal SIGKILL -f "$RUSTDESK_EXECUTABLE"
    sleep 1
  fi

  if systemctl is-active --quiet "$RUSTDESK_SERVICE_NAME"; then
    echo "ERROR: RustDesk service ($RUSTDESK_SERVICE_NAME) could NOT be stopped. Please stop it manually and re-run."
    return 1
  else
    echo "INFO: RustDesk service is stopped or was not running."
    return 0
  fi
}

start_rustdesk() {
  echo "INFO: Starting RustDesk service ($RUSTDESK_SERVICE_NAME)..."
  systemctl start "$RUSTDESK_SERVICE_NAME"
  sleep 3 # Give RustDesk time to initialize
  if systemctl is-active --quiet "$RUSTDESK_SERVICE_NAME"; then
    echo "INFO: Service started successfully."
    return 0
  else
    echo "ERROR: Service $RUSTDESK_SERVICE_NAME failed to start."
    echo "       Please check: systemctl status $RUSTDESK_SERVICE_NAME"
    echo "       And: journalctl -xeu $RUSTDESK_SERVICE_NAME"
    return 1
  fi
}

# Variables to track script state for cleanup
original_config_backup_path=""
script_error_occurred=false

cleanup_on_exit() {
    if $script_error_occurred; then
        echo ""
        echo "--- ERROR OCCURRED ---"
        echo "INFO: An error occurred. The RustDesk service might be stopped or config in an intermediate state."
        if [ -n "$original_config_backup_path" ] && [ -f "$original_config_backup_path" ]; then
            echo "INFO: An original config backup exists at: $original_config_backup_path"
            echo "      To restore: sudo systemctl stop $RUSTDESK_SERVICE_NAME; sudo chattr -i $RUSTDESK_CONFIG_FILE; sudo cp '$original_config_backup_path' '$RUSTDESK_CONFIG_FILE'; sudo systemctl start $RUSTDESK_SERVICE_NAME"
        fi
    fi
    echo "INFO: Script finished."
}
trap cleanup_on_exit EXIT
trap 'script_error_occurred=true; cleanup_on_exit' ERR SIGINT SIGTERM

# --- Main Script Logic ---
echo "--- RustDesk Advanced ID Modifier (V4 - Cleaned) ---"
echo "Target Config: $RUSTDESK_CONFIG_FILE"
echo "WARNING: HIGHLY EXPERIMENTAL! This might break your RustDesk installation if the new enc_id is incompatible with other settings."
echo ""

if [ ! -x "$RUSTDESK_EXECUTABLE" ]; then
  echo "ERROR: RustDesk executable not found at '$RUSTDESK_EXECUTABLE' or not executable."; script_error_occurred=true; exit 1
fi

read -r -p "Enter your DESIRED PLAIN RustDesk ID (e.g., sag.ubu): " desired_plain_id
if [ -z "$desired_plain_id" ]; then
  echo "ERROR: Desired plain ID cannot be empty."; script_error_occurred=true; exit 1
fi

read -r -p "Confirm to proceed with ID '$desired_plain_id'? (yes/NO): " confirm
if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
  echo "Operation cancelled."; exit 0
fi

# --- Phase 1: Generate NEW enc_id based on PLAIN desired ID ---
echo ""
echo ">>> Phase 1: Generating new enc_id for '$desired_plain_id'..."
if ! stop_rustdesk; then script_error_occurred=true; exit 1; fi

original_config_existed=false
if [ -f "$RUSTDESK_CONFIG_FILE" ]; then
  original_config_existed=true
  original_config_backup_path="${RUSTDESK_CONFIG_FILE}.adv_id_V4_$(date +%Y%m%d%H%M%S).bak"
  echo "INFO: Backing up '$RUSTDESK_CONFIG_FILE' to '$original_config_backup_path'..."
  if ! cp "$RUSTDESK_CONFIG_FILE" "$original_config_backup_path"; then
    echo "ERROR: Failed to create backup. Aborting."; script_error_occurred=true; exit 1
  fi
  echo "INFO: Ensuring '$RUSTDESK_CONFIG_FILE' is mutable..."
  chattr -i "$RUSTDESK_CONFIG_FILE" 2>/dev/null || true
else
  echo "INFO: No existing config at '$RUSTDESK_CONFIG_FILE'. A new one will be created by RustDesk."
fi

echo "INFO: Writing minimal ID ('id = \"$desired_plain_id\"') to '$RUSTDESK_CONFIG_FILE'..."
if ! echo "id = \"$desired_plain_id\"" > "$RUSTDESK_CONFIG_FILE"; then
  echo "ERROR: Failed to write minimal config. Aborting."; script_error_occurred=true; exit 1
fi
chown root:root "$RUSTDESK_CONFIG_FILE"; chmod 600 "$RUSTDESK_CONFIG_FILE"

echo "INFO: Starting RustDesk to regenerate full configuration..."
if ! start_rustdesk; then
    echo "ERROR: RustDesk failed to start for config regeneration. Cannot proceed."; script_error_occurred=true; exit 1
fi
echo "INFO: Waiting for RustDesk to regenerate config (approx. 7 seconds)..."
sleep 7
if ! stop_rustdesk; then echo "WARN: Failed to stop RustDesk cleanly after regeneration."; fi # Continue to extract

echo "INFO: Extracting newly generated enc_id from '$RUSTDESK_CONFIG_FILE'..."
if [ ! -f "$RUSTDESK_CONFIG_FILE" ]; then
    echo "ERROR: $RUSTDESK_CONFIG_FILE not found after regeneration. Aborting."; script_error_occurred=true; exit 1
fi
newly_generated_enc_id=$(grep -m1 "^enc_id\s*=\s*'" "$RUSTDESK_CONFIG_FILE" | sed -n "s/^enc_id\s*=\s*'\([^']*\)'.*/\1/p")

if [ -z "$newly_generated_enc_id" ]; then
  echo "ERROR: Could not extract newly generated enc_id from '$RUSTDESK_CONFIG_FILE'."
  echo "       Contents of $RUSTDESK_CONFIG_FILE after regeneration attempt:"
  cat "$RUSTDESK_CONFIG_FILE"
  script_error_occurred=true; exit 1
fi
echo "------------------------------------------------------------"
echo "SUCCESS (Phase 1): Newly generated enc_id: '$newly_generated_enc_id'"
echo "------------------------------------------------------------"

# --- Phase 2: Substitute NEW_ENC_ID into ORIGINAL settings (if original existed) ---
echo ""
echo ">>> Phase 2: Preparing final configuration..."

final_config_was_regenerated_only=false
if $original_config_existed && [ -f "$original_config_backup_path" ]; then
    echo "INFO: Restoring original settings from '$original_config_backup_path' to '$RUSTDESK_CONFIG_FILE'..."
    if ! cp "$original_config_backup_path" "$RUSTDESK_CONFIG_FILE"; then
        echo "ERROR: Failed to restore original settings from backup. Aborting."; script_error_occurred=true; exit 1
    fi
    chown root:root "$RUSTDESK_CONFIG_FILE"; chmod 600 "$RUSTDESK_CONFIG_FILE"
    chattr -i "$RUSTDESK_CONFIG_FILE" 2>/dev/null || true

    echo "INFO: Modifying '$RUSTDESK_CONFIG_FILE' (original structure) to use new enc_id: '$newly_generated_enc_id'..."
    if grep -q "^enc_id\s*=\s*'" "$RUSTDESK_CONFIG_FILE"; then
        if ! sed -i "s~^\(enc_id\s*=\s*'\)[^']*'\(\s*$\)~\1${newly_generated_enc_id}'\2~" "$RUSTDESK_CONFIG_FILE"; then
            echo "ERROR: sed failed to substitute new enc_id. Aborting."; script_error_occurred=true; exit 1
        fi
        echo "INFO: Substituted newly generated enc_id into your original config structure."
        echo "      WARNING: This mixed state (new enc_id, old salt/key_pair/password) is cryptographically risky."
    else
        echo "ERROR: Original config backup ('$original_config_backup_path') did not have an 'enc_id' line to replace."
        echo "       Cannot inject new enc_id into old structure as intended. Aborting."; script_error_occurred=true; exit 1
    fi
else
    echo "INFO: No original config was backed up (or it was empty). Using the fully RustDesk-regenerated config."
    echo "      This config has new enc_id AND default (empty) salt, key_pair, password."
    final_config_was_regenerated_only=true
    # $RUSTDESK_CONFIG_FILE already contains the fully regenerated content. No further 'sed' needed.
fi

# --- Phase 3: Finalizing ---
echo ""
echo ">>> Phase 3: Finalizing..."
echo "INFO: Making final configuration '$RUSTDESK_CONFIG_FILE' immutable..."
if ! chattr +i "$RUSTDESK_CONFIG_FILE"; then
  echo "ERROR: Failed to make '$RUSTDESK_CONFIG_FILE' immutable."; script_error_occurred=true; exit 1
fi
echo "INFO: Configuration file is now immutable."

if ! start_rustdesk; then script_error_occurred=true; exit 1; fi

echo ""
echo "--- PROCESS COMPLETED ---"
final_reported_id=$("$RUSTDESK_EXECUTABLE" --get-id 2>/dev/null)
echo "RustDesk has been restarted. The reported ID is now: '$final_reported_id'"
echo "(Your desired plain ID was: '$desired_plain_id')"
echo "The '$RUSTDESK_CONFIG_FILE' (containing enc_id: '$newly_generated_enc_id') is now locked."

if $original_config_existed && [ -f "$original_config_backup_path" ] && [ "$final_config_was_regenerated_only" = false ]; then
    echo "FINAL CONFIG STATE: Based on your original settings, but with enc_id replaced."
    echo "!! REMEMBER THE WARNINGS ABOUT CRYPTOGRAPHIC INCONSISTENCY !! "
else
    echo "FINAL CONFIG STATE: Fully regenerated by RustDesk (default password/salt/key_pair)."
fi

script_completed_successfully="true" # Mark as successful
trap - ERR SIGINT SIGTERM # Clear trap
exit 0
