#!/bin/bash

# ==============================================================================
# RustDesk ID Modifier for macOS - V3.2 (Fixed enc_id extraction)
#
# Process:
# 1. User inputs a PLAIN desired ID (e.g., "MyMacID").
# 2. Script stops RustDesk, backs up the current config (to save the original password).
# 3. It writes a minimal config with ONLY the plain ID to RustDesk.toml.
# 4. Starts RustDesk, allowing it to fully regenerate RustDesk.toml. This new
#    file will have a new enc_id, new salt, new key_pair, and an EMPTY password.
# 5. Stops RustDesk.
# 6. Extracts the ORIGINAL password line from the backup.
# 7. Modifies the NEWLY REGENERATED RustDesk.toml by replacing its (empty)
#    password line with the ORIGINAL password line.
# 8. Makes this final modified (password-restored) config file immutable.
# 9. Starts RustDesk for use.
#
# WARNING: This process will use a newly generated cryptographic identity
# (enc_id, salt, key_pair) based on your plain ID. Only the password hash
# from your original configuration is preserved.
# ==============================================================================

# --- Configuration Variables ---
HOME_DIR="$HOME" # Gets current user's home directory
RUSTDESK_PREFERENCES_DIR="$HOME_DIR/Library/Preferences/com.carriez.RustDesk"
RUSTDESK_CONFIG_FILE="$RUSTDESK_PREFERENCES_DIR/RustDesk.toml"
RUSTDESK_APP_NAME="RustDesk"

# Attempt to find the RustDesk executable
RUSTDESK_APP_PATH=$(mdfind "kMDItemCFBundleIdentifier == 'com.carriez.RustDesk'" | head -n 1)
RUSTDESK_EXECUTABLE=""
if [ -n "$RUSTDESK_APP_PATH" ] && [ -x "$RUSTDESK_APP_PATH/Contents/MacOS/RustDesk" ]; then
    RUSTDESK_EXECUTABLE="$RUSTDESK_APP_PATH/Contents/MacOS/RustDesk"
else
    if [ -x "/Applications/RustDesk.app/Contents/MacOS/RustDesk" ]; then # Common fallback
        RUSTDESK_EXECUTABLE="/Applications/RustDesk.app/Contents/MacOS/RustDesk"
    fi
fi

# --- Helper Functions ---
stop_rustdesk() {
  echo "INFO: Attempting to stop RustDesk application..."
  if pgrep -f "$RUSTDESK_APP_NAME" > /dev/null || ( [ -n "$RUSTDESK_EXECUTABLE" ] && pgrep -f "$(basename "$RUSTDESK_EXECUTABLE" 2>/dev/null)" > /dev/null ); then
    osascript -e "tell application \"$RUSTDESK_APP_NAME\" to if it is running then quit" &>/dev/null
    echo "INFO: Sent quit command via AppleScript. Waiting a moment..."
    sleep 3 # Give it time to quit gracefully

    if pgrep -f "$RUSTDESK_APP_NAME" > /dev/null || ( [ -n "$RUSTDESK_EXECUTABLE" ] && pgrep -f "$(basename "$RUSTDESK_EXECUTABLE")" > /dev/null ); then
      echo "INFO: RustDesk still running. Attempting pkill..."
      pkill -f "$RUSTDESK_APP_NAME" # General app name
      if [ -n "$RUSTDESK_EXECUTABLE" ]; then
          pkill -f "$(basename "$RUSTDESK_EXECUTABLE")" # Specific executable
      fi
      sleep 1
      if pgrep -f "$RUSTDESK_APP_NAME" > /dev/null || ( [ -n "$RUSTDESK_EXECUTABLE" ] && pgrep -f "$(basename "$RUSTDESK_EXECUTABLE")" > /dev/null ); then
          echo "WARN: RustDesk might still be running after pkill attempts."
      else
          echo "INFO: RustDesk application stop attempts completed (pkill)."
      fi
    else
      echo "INFO: RustDesk application quit gracefully."
    fi
  else
    echo "INFO: RustDesk application was not running."
  fi
}

start_rustdesk() {
  echo "INFO: Starting RustDesk application ($RUSTDESK_APP_NAME)..."
  if open -a "$RUSTDESK_APP_NAME"; then
    sleep 5 # Give RustDesk more time to initialize GUI and write config on macOS
    if pgrep -f "$RUSTDESK_APP_NAME" > /dev/null || ( [ -n "$RUSTDESK_EXECUTABLE" ] && pgrep -f "$(basename "$RUSTDESK_EXECUTABLE")" > /dev/null ); then
        echo "INFO: RustDesk application started (or was already running)."
        return 0
    else
        echo "ERROR: RustDesk application did not appear to start after 'open -a' command."
        return 1
    fi
  else
    echo "ERROR: 'open -a $RUSTDESK_APP_NAME' command failed."
    echo "       Please ensure RustDesk is installed correctly in Applications."
    return 1
  fi
}

make_mutable() {
    local file_to_modify="$1"
    if [ -f "$file_to_modify" ]; then
        echo "INFO: Ensuring '$file_to_modify' is mutable (removing uchg flag)..."
        chflags nouchg "$file_to_modify" 2>/dev/null || echo "WARN: Could not remove uchg flag from '$file_to_modify' (may not have been set, or permission issue)."
    fi
}

make_immutable() {
    local file_to_modify="$1"
    echo "INFO: Making '$file_to_modify' immutable (setting uchg flag)..."
    if ! chflags uchg "$file_to_modify"; then
        echo "ERROR: Failed to make '$file_to_modify' immutable. Check permissions."
        return 1
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
            echo "      To restore: Quit RustDesk, run 'chflags nouchg \"$RUSTDESK_CONFIG_FILE\"', then 'cp \"$original_config_backup_path\" \"$RUSTDESK_CONFIG_FILE\"', then start RustDesk."
        fi
    fi
    echo "INFO: Script finished."
}
trap cleanup_on_exit EXIT
trap 'script_error_occurred=true; cleanup_on_exit' ERR SIGINT SIGTERM


# --- Main Script Logic ---
echo "--- RustDesk macOS ID Modifier (V3.2 - Fixed enc_id extraction) ---"
echo "Target Config File: $RUSTDESK_CONFIG_FILE"
echo "!! WARNING: This script will make RustDesk regenerate its cryptographic identity !!"
echo "!! (enc_id, salt, key_pair) based on your plain ID. Only your original password !!"
echo "!! hash will be attempted to be restored into the new config.                 !!"
echo ""

if [ -z "$RUSTDESK_EXECUTABLE" ]; then
  echo "ERROR: RustDesk command-line executable could not be found automatically."
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

read -r -p "Confirm to proceed with ID '$desired_plain_id'? This will reset crypto keys and attempt to restore only your password. (yes/NO): " confirm
if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
  echo "Operation cancelled."; exit 0
fi

# --- Phase 1: Let RustDesk Regenerate a Full New Config ---
echo ""
echo ">>> Phase 1: Triggering RustDesk to regenerate config for ID '$desired_plain_id'..."
stop_rustdesk

original_config_existed=false
mkdir -p "$RUSTDESK_PREFERENCES_DIR" # Ensure directory exists

if [ -f "$RUSTDESK_CONFIG_FILE" ]; then
  original_config_existed=true
  original_config_backup_path="${RUSTDESK_CONFIG_FILE}.macos_id_v32_$(date +%Y%m%d%H%M%S).bak"
  echo "INFO: Backing up '$RUSTDESK_CONFIG_FILE' to '$original_config_backup_path' (to save original password)..."
  if ! cp "$RUSTDESK_CONFIG_FILE" "$original_config_backup_path"; then
    echo "ERROR: Failed to create backup. Aborting."; script_error_occurred=true; exit 1
  fi
  make_mutable "$RUSTDESK_CONFIG_FILE"
else
  echo "INFO: No existing config at '$RUSTDESK_CONFIG_FILE'. A new one will be created by RustDesk (password will be default empty)."
fi

echo "INFO: Writing minimal ID ('id = \"$desired_plain_id\"') to '$RUSTDESK_CONFIG_FILE'..."
if ! echo "id = \"$desired_plain_id\"" > "$RUSTDESK_CONFIG_FILE"; then
  echo "ERROR: Failed to write minimal config. Aborting."; script_error_occurred=true; exit 1
fi

echo "INFO: Starting RustDesk to regenerate full configuration..."
if ! start_rustdesk; then
    echo "ERROR: RustDesk failed to start for config regeneration. Cannot proceed."; script_error_occurred=true; exit 1
fi
echo "INFO: Waiting for RustDesk to regenerate config (approx. 10 seconds on macOS)..."
sleep 10 
stop_rustdesk

echo "INFO: Extracting newly generated enc_id from '$RUSTDESK_CONFIG_FILE'..."
if [ ! -f "$RUSTDESK_CONFIG_FILE" ]; then
    echo "ERROR: $RUSTDESK_CONFIG_FILE not found after regeneration. Aborting."; script_error_occurred=true; exit 1
fi

# FIXED: Using grep instead of awk for more reliable extraction
newly_generated_enc_id=$(grep -E "^enc_id" "$RUSTDESK_CONFIG_FILE" | cut -d "'" -f 2)

if [ -z "$newly_generated_enc_id" ]; then
  echo "ERROR: Could not extract newly generated enc_id from '$RUSTDESK_CONFIG_FILE' using grep."
  echo "       Contents of $RUSTDESK_CONFIG_FILE after regeneration attempt:"
  cat "$RUSTDESK_CONFIG_FILE"
  script_error_occurred=true; exit 1
fi
echo "------------------------------------------------------------"
echo "SUCCESS (Phase 1): Newly generated enc_id: '$newly_generated_enc_id'"
echo "------------------------------------------------------------"

# --- Phase 2: Restoring original password into the newly regenerated config ---
echo ""
echo ">>> Phase 2: Restoring original password into the newly regenerated config..."

make_mutable "$RUSTDESK_CONFIG_FILE" # Ensure the newly generated file is writable

original_password_line=""
if $original_config_existed && [ -f "$original_config_backup_path" ]; then
    echo "INFO: Attempting to extract original password line from backup: $original_config_backup_path"
    # FIXED: Using grep instead of awk to extract the full password line
    original_password_line=$(grep -E "^password" "$original_config_backup_path")
    if [ -n "$original_password_line" ]; then
        echo "INFO: Original password line found: [$original_password_line]"
    else
        echo "WARN: Could not find 'password = ...' line in original backup. Password in new config will remain default (empty)."
    fi
else
    echo "INFO: No original config backup to restore password from. Password in new config will be default (empty)."
fi

if [ -n "$original_password_line" ]; then
    echo "INFO: Modifying newly regenerated '$RUSTDESK_CONFIG_FILE' to restore original password..."
    if grep -q "^password" "$RUSTDESK_CONFIG_FILE"; then
        # macOS sed requires -i '' for in-place editing without backup
        # Escape the original_password_line for use in sed replacement string
        # This handles slashes and ampersands in the password hash
        escaped_replacement_line=$(printf '%s\n' "$original_password_line" | sed 's/[\/&]/\\&/g')
        if ! sed -i '' "s/^password.*/$escaped_replacement_line/" "$RUSTDESK_CONFIG_FILE"; then
            echo "ERROR: sed failed to restore password. Password in new config might be default (empty)."
        else
            echo "INFO: Original password line restored into the new config."
        fi
    else
        echo "WARN: No 'password = ...' line found in the newly regenerated config to replace. Appending original password line."
        echo "$original_password_line" >> "$RUSTDESK_CONFIG_FILE"
    fi
else
    echo "INFO: Proceeding with default (empty) password in the new config."
fi

# --- Phase 3: Finalizing ---
echo ""
echo ">>> Phase 3: Finalizing..."
if ! make_immutable "$RUSTDESK_CONFIG_FILE"; then
    script_error_occurred=true; exit 1
fi

if ! start_rustdesk; then script_error_occurred=true; exit 1; fi

echo ""
echo "--- PROCESS COMPLETED ---"
final_reported_id=""
# For display, re-extract the enc_id from the final locked file
final_enc_id_for_display=$(grep -E "^enc_id" "$RUSTDESK_CONFIG_FILE" | cut -d "'" -f 2)

if [ -n "$RUSTDESK_EXECUTABLE" ]; then
    final_reported_id=$("$RUSTDESK_EXECUTABLE" --get-id 2>/dev/null)
fi
echo "RustDesk has been restarted. The reported ID by command-line is: '$final_reported_id'"
echo "(Your desired plain ID was: '$desired_plain_id')"
echo "The '$RUSTDESK_CONFIG_FILE' (containing enc_id: '$final_enc_id_for_display') is now locked (immutable)."
echo "Your original password (if found in backup) should be restored. Other settings (salt, key_pair) are newly generated."
echo ""
echo "To Revert (Example):"
echo "  (First, quit RustDesk application)"
echo "  chflags nouchg \"$RUSTDESK_CONFIG_FILE\""
if $original_config_existed && [ -f "$original_config_backup_path" ]; then
  echo "  cp \"$original_config_backup_path\" \"$RUSTDESK_CONFIG_FILE\"  (This was your config before this script ran)"
else
  echo "  (No specific original config was backed up from this run if it didn't exist initially)"
fi
echo "  (Then, restart RustDesk application: open -a \"$RUSTDESK_APP_NAME\")"

script_completed_successfully="true" # Mark as successful
trap - ERR SIGINT SIGTERM # Clear trap on successful completion
exit 0