#!/bin/bash

# ==============================================================================
# RustDesk ID Modifier for macOS - Advanced (User-Specified Logic)
#
# Process:
# 1. User inputs a PLAIN desired ID (e.g., "myMacID").
# 2. Script makes RustDesk generate a NEW enc_id corresponding to this PLAIN ID
#    by temporarily giving RustDesk a minimal config. This will reset salt,
#    key_pair, password etc., in that intermediate, regenerated config.
# 3. Script extracts this NEWLY_GENERATED_ENC_ID.
# 4. IF an ORIGINAL config existed before this script ran, that original config
#    is restored, and THEN ONLY its 'enc_id' line is replaced with the
#    NEWLY_GENERATED_ENC_ID. Other original settings are kept.
# 5. This final modified config file is made immutable using 'chflags uchg'.
#
# !! WARNING !! THIS IS HIGHLY EXPERIMENTAL AND RISKY !!
# Forcing a new enc_id while keeping old salt/key_pair from a different
# identity is very likely to create an inconsistent and NON-FUNCTIONAL
# cryptographic state for RustDesk.
# PROCEED WITH EXTREME CAUTION AND ENSURE YOU HAVE MANUAL BACKUPS.
# ==============================================================================

# --- Configuration Variables ---
CURRENT_USER=$(whoami)
RUSTDESK_PREFERENCES_DIR="/Users/$CURRENT_USER/Library/Preferences/com.carriez.RustDesk"
RUSTDESK_CONFIG_FILE="$RUSTDESK_PREFERENCES_DIR/RustDesk.toml"
RUSTDESK_APP_NAME="RustDesk" # As used by `open -a` and `pkill`

# Attempt to find the RustDesk executable for command-line operations
RUSTDESK_APP_PATH=$(mdfind "kMDItemCFBundleIdentifier == 'com.carriez.RustDesk'" | head -n 1)
RUSTDESK_EXECUTABLE=""
if [ -n "$RUSTDESK_APP_PATH" ] && [ -x "$RUSTDESK_APP_PATH/Contents/MacOS/RustDesk" ]; then
    RUSTDESK_EXECUTABLE="$RUSTDESK_APP_PATH/Contents/MacOS/RustDesk"
else
    # Fallback or common location if mdfind fails or for non-standard installs
    if [ -x "/Applications/RustDesk.app/Contents/MacOS/RustDesk" ]; then
        RUSTDESK_EXECUTABLE="/Applications/RustDesk.app/Contents/MacOS/RustDesk"
    fi
fi

# --- Check if running as root (sudo might be needed for chflags if perms are weird, though usually not for user files) ---
# For this script, we will attempt chflags without sudo first. If it fails, the user might need to adjust.
# However, if RustDesk is managed by a system-level launch agent, sudo would be needed for launchctl.
# This script assumes a user-level application for now.

# --- Helper Functions ---
stop_rustdesk() {
  echo "INFO: Attempting to stop RustDesk application..."
  # Try graceful quit first
  osascript -e "tell application \"$RUSTDESK_APP_NAME\" to if it is running then quit" &>/dev/null
  sleep 2 # Give it time to quit gracefully

  # Check if still running and pkill if necessary
  if pgrep -f "$RUSTDESK_APP_NAME" > /dev/null || pgrep -f "$(basename "$RUSTDESK_EXECUTABLE" 2>/dev/null)" > /dev/null; then
    echo "INFO: RustDesk still running or executable process found. Attempting pkill..."
    pkill -f "$RUSTDESK_APP_NAME" # More general
    if [ -n "$RUSTDESK_EXECUTABLE" ]; then
        pkill -f "$(basename "$RUSTDESK_EXECUTABLE")" # More specific if executable found
    fi
    sleep 1
    if pgrep -f "$RUSTDESK_APP_NAME" > /dev/null || ( [ -n "$RUSTDESK_EXECUTABLE" ] && pgrep -f "$(basename "$RUSTDESK_EXECUTABLE")" > /dev/null ); then
        echo "WARN: RustDesk might still be running after pkill attempts."
    else
        echo "INFO: RustDesk application stop attempts completed."
    fi
  else
    echo "INFO: RustDesk application was not running or quit gracefully."
  fi
}

start_rustdesk() {
  echo "INFO: Starting RustDesk application ($RUSTDESK_APP_NAME)..."
  if open -a "$RUSTDESK_APP_NAME"; then
    sleep 3 # Give RustDesk time to initialize
    # Check if it actually launched (basic check)
    if pgrep -f "$RUSTDESK_APP_NAME" > /dev/null || ( [ -n "$RUSTDESK_EXECUTABLE" ] && pgrep -f "$(basename "$RUSTDESK_EXECUTABLE")" > /dev/null ); then
        echo "INFO: RustDesk application started (or was already running)."
        return 0
    else
        echo "ERROR: RustDesk application did not appear to start after 'open -a' command."
        return 1
    fi
  else
    echo "ERROR: 'open -a $RUSTDESK_APP_NAME' command failed."
    echo "       Please ensure RustDesk is installed correctly."
    return 1
  fi
}

make_mutable() {
    local file_to_modify="$1"
    if [ -f "$file_to_modify" ]; then
        echo "INFO: Ensuring '$file_to_modify' is mutable (removing uchg flag)..."
        chflags nouchg "$file_to_modify" 2>/dev/null || echo "WARN: Could not remove uchg flag (may not have been set, or permission issue)."
    fi
}

make_immutable() {
    local file_to_modify="$1"
    echo "INFO: Making '$file_to_modify' immutable (setting uchg flag)..."
    if ! chflags uchg "$file_to_modify"; then
        echo "ERROR: Failed to make '$file_to_modify' immutable. Check permissions."
        echo "       You might need to run 'sudo chflags uchg \"$file_to_modify\"' manually if this script isn't run with sufficient privileges for this specific file."
        return 1 # Indicate failure
    fi
    echo "INFO: File '$file_to_modify' is now immutable."
    return 0
}


# Variables to track script state for cleanup
original_config_backup_path=""
script_error_occurred=false

cleanup_on_exit() {
    if $script_error_occurred; then
        echo ""
        echo "--- ERROR OCCURRED ---"
        echo "INFO: An error occurred. RustDesk or its config might be in an intermediate state."
        if [ -n "$original_config_backup_path" ] && [ -f "$original_config_backup_path" ]; then
            echo "INFO: An original config backup exists at: $original_config_backup_path"
            echo "      To restore: stop RustDesk, run 'chflags nouchg \"$RUSTDESK_CONFIG_FILE\"', then 'cp \"$original_config_backup_path\" \"$RUSTDESK_CONFIG_FILE\"', then start RustDesk."
        fi
    fi
    echo "INFO: Script finished."
}
trap cleanup_on_exit EXIT
trap 'script_error_occurred=true; cleanup_on_exit' ERR SIGINT SIGTERM


# --- Main Script Logic ---
echo "--- RustDesk macOS ID Modifier (Advanced - V1) ---"
echo "Target Config Dir: $RUSTDESK_PREFERENCES_DIR"
echo "Target Config File: $RUSTDESK_CONFIG_FILE"
echo "!! WARNING: VERY HIGHLY EXPERIMENTAL AND RISKY !! "
echo "This script attempts to inject a RustDesk-generated 'enc_id' (based on your plain ID)"
echo "into your *original* config's structure, keeping other original settings."
echo "This has a high chance of creating an unusable/insecure RustDesk state due to"
echo "mismatched cryptographic components (new enc_id vs old salt/key_pair)."
echo ""

if [ -z "$RUSTDESK_EXECUTABLE" ]; then
  echo "ERROR: RustDesk command-line executable could not be found automatically."
  echo "       Please set the RUSTDESK_EXECUTABLE variable manually in the script."
  script_error_occurred=true; exit 1
elif [ ! -x "$RUSTDESK_EXECUTABLE" ]; then
  echo "ERROR: RustDesk executable found at '$RUSTDESK_EXECUTABLE' is not executable."
  script_error_occurred=true; exit 1
fi
echo "INFO: Using RustDesk executable: $RUSTDESK_EXECUTABLE"


read -r -p "Enter your DESIRED PLAIN RustDesk ID (e.g., MyMacID): " desired_plain_id
if [ -z "$desired_plain_id" ]; then
  echo "ERROR: Desired plain ID cannot be empty."; script_error_occurred=true; exit 1
fi

read -r -p "Confirm to proceed with this complex and risky operation for ID '$desired_plain_id'? (yes/NO): " confirm
if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
  echo "Operation cancelled."; exit 0
fi

# --- Phase 1: Generate NEW enc_id based on PLAIN desired ID ---
echo ""
echo ">>> Phase 1: Generating new enc_id for '$desired_plain_id'..."
stop_rustdesk

original_config_existed=false
# Ensure preferences directory exists
mkdir -p "$RUSTDESK_PREFERENCES_DIR"

if [ -f "$RUSTDESK_CONFIG_FILE" ]; then
  original_config_existed=true
  original_config_backup_path="${RUSTDESK_CONFIG_FILE}.adv_id_macos_$(date +%Y%m%d%H%M%S).bak"
  echo "INFO: Backing up '$RUSTDESK_CONFIG_FILE' to '$original_config_backup_path'..."
  if ! cp "$RUSTDESK_CONFIG_FILE" "$original_config_backup_path"; then
    echo "ERROR: Failed to create backup. Aborting."; script_error_occurred=true; exit 1
  fi
  make_mutable "$RUSTDESK_CONFIG_FILE"
else
  echo "INFO: No existing config at '$RUSTDESK_CONFIG_FILE'. A new one will be created by RustDesk."
fi

echo "INFO: Writing minimal ID ('id = \"$desired_plain_id\"') to '$RUSTDESK_CONFIG_FILE' for enc_id generation..."
if ! echo "id = \"$desired_plain_id\"" > "$RUSTDESK_CONFIG_FILE"; then
  echo "ERROR: Failed to write minimal config. Aborting."; script_error_occurred=true; exit 1
fi
# No chown/chmod needed typically for user's own Library files.

echo "INFO: Starting RustDesk to regenerate full configuration..."
if ! start_rustdesk; then
    echo "ERROR: RustDesk failed to start for config regeneration. Cannot proceed."; script_error_occurred=true; exit 1
fi
echo "INFO: Waiting for RustDesk to regenerate config (approx. 10 seconds on macOS)..."
sleep 10 # Give more time on macOS for app to launch and write config
stop_rustdesk

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

if $original_config_existed && [ -f "$original_config_backup_path" ]; then
    echo "INFO: Restoring your original settings from '$original_config_backup_path' to '$RUSTDESK_CONFIG_FILE'..."
    if ! cp "$original_config_backup_path" "$RUSTDESK_CONFIG_FILE"; then
        echo "ERROR: Failed to restore original settings from backup. Aborting."; script_error_occurred=true; exit 1
    fi
    make_mutable "$RUSTDESK_CONFIG_FILE" # Ensure writable for sed

    echo "INFO: Modifying '$RUSTDESK_CONFIG_FILE' (original structure) to use new enc_id: '$newly_generated_enc_id'..."
    # Use sed -i '' for macOS compatibility
    if grep -q "^enc_id\s*=\s*'" "$RUSTDESK_CONFIG_FILE"; then
        if ! sed -i '' "s~^\(enc_id\s*=\s*'\)[^']*'\(\s*$\)~\1${newly_generated_enc_id}'\2~" "$RUSTDESK_CONFIG_FILE"; then
            echo "ERROR: sed failed to substitute new enc_id. Aborting."; script_error_occurred=true; exit 1
        fi
        echo "INFO: Substituted newly generated enc_id into your original config structure."
        echo "      WARNING: This mixed state (new enc_id, old salt/key_pair/password) is cryptographically risky."
    else
        echo "ERROR: Original config backup ('$original_config_backup_path') did not have an 'enc_id' line to replace."
        echo "       Cannot inject new enc_id into old structure. Aborting."; script_error_occurred=true; exit 1
    fi
else
    echo "INFO: No original config was backed up (or it was empty). Using the fully RustDesk-regenerated config."
    echo "      This config has new enc_id AND default (empty) salt, key_pair, password."
    # $RUSTDESK_CONFIG_FILE already contains the fully regenerated content. No further 'sed' needed.
fi

# --- Phase 3: Finalizing ---
echo ""
echo ">>> Phase 3: Finalizing..."
if ! make_immutable "$RUSTDESK_CONFIG_FILE"; then
    script_error_occurred=true; exit 1 # make_immutable will print its own error
fi

if ! start_rustdesk; then script_error_occurred=true; exit 1; fi

echo ""
echo "--- PROCESS COMPLETED ---"
final_reported_id=""
if [ -n "$RUSTDESK_EXECUTABLE" ]; then
    final_reported_id=$("$RUSTDESK_EXECUTABLE" --get-id 2>/dev/null)
fi
echo "RustDesk has been restarted. The reported ID by command-line is: '$final_reported_id'"
echo "(Your desired plain ID was: '$desired_plain_id')"
echo "The '$RUSTDESK_CONFIG_FILE' (containing enc_id: '$newly_generated_enc_id') is now locked (immutable)."

if $original_config_existed && [ -f "$original_config_backup_path" ]; then # Check if original config was used for merge
    # Check if the final config is different from the fully regenerated one (i.e., if merge happened)
    temp_regenerated_content_check=$(grep -m1 "^enc_id\s*=\s*'$newly_generated_enc_id'" "$RUSTDESK_CONFIG_FILE" && \
                                 grep -m1 "^salt\s*=\s*''" "$RUSTDESK_CONFIG_FILE" && \
                                 grep -m1 "^password\s*=\s*''" "$RUSTDESK_CONFIG_FILE" )
    if [ -z "$temp_regenerated_content_check" ] || ! (grep -q "^salt\s*=\s*''" "$RUSTDESK_CONFIG_FILE" && grep -q "^password\s*=\s*''" "$RUSTDESK_CONFIG_FILE"); then
      echo "FINAL CONFIG STATE: Based on your original settings, but with enc_id replaced."
      echo "!! REMEMBER THE WARNINGS ABOUT CRYPTOGRAPHIC INCONSISTENCY !! "
    else
      echo "FINAL CONFIG STATE: Appears to be the fully RustDesk-regenerated config (default password/salt/key_pair)."
    fi
else
    echo "FINAL CONFIG STATE: Fully regenerated by RustDesk based on '$desired_plain_id' (default password/salt/key_pair)."
fi

echo ""
echo "To Revert (Example):"
echo "  (First, quit RustDesk application)"
echo "  chflags nouchg \"$RUSTDESK_CONFIG_FILE\""
if $original_config_existed && [ -f "$original_config_backup_path" ]; then
  echo "  cp \"$original_config_backup_path\" \"$RUSTDESK_CONFIG_FILE\"  (This was your config before this script ran)"
else
  echo "  (No specific original config was backed up from this run if it didn't exist initially)"
  echo "  (You might want to delete \"$RUSTDESK_CONFIG_FILE\" and let RustDesk create a fresh default one, or restore another manual backup)"
fi
echo "  (Then, restart RustDesk application: open -a \"$RUSTDESK_APP_NAME\")"

script_completed_successfully="true" # Mark as successful
trap - ERR SIGINT SIGTERM # Clear trap on successful completion
exit 0
