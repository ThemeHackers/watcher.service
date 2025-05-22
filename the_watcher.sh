#!/bin/bash

CONFIG_FILE="/etc/watcher.conf"
TEMP_FILE="/tmp/failed_attempts.log"
NOTIFIED_IPS="/tmp/notified_ips.log"
LOCAL_LOG="/var/log/security_alerts.log"
THRESHOLD=10
CHECK_INTERVAL=10
DISCORD_USERNAME="the_watcher.sh"
DISCORD_AVATAR="https://ucarecdn.com/a9598b0a-704e-4dd5-b37a-91e515936b77/-/preview/500x500/"
WEBHOOK_URL=""
TEST_MODE=0

if [ "$1" = "--test" ]; then
  TEST_MODE=1
  echo "[$(date)] Running in test mode. No webhook calls will be made."
fi

create_file_if_missing() {
  local file="$1"
  local perms="$2"
  if [ ! -f "$file" ]; then
    echo "[$(date)] File $file does not exist. Creating it..."
    touch "$file" 2>/dev/null || {
      echo "[$(date)] Error: Failed to create $file. Check permissions."
      exit 1
    }
    chmod "$perms" "$file" 2>/dev/null || {
      echo "[$(date)] Error: Failed to set permissions on $file."
      exit 1
    }
    echo "[$(date)] Created $file with permissions $perms"
  fi
}

create_file_if_missing "$CONFIG_FILE" "600"
if [ ! -s "$CONFIG_FILE" ]; then
  echo "[$(date)] Warning: $CONFIG_FILE is empty. Please add WEBHOOK_URL."
fi
create_file_if_missing "$TEMP_FILE" "644"
create_file_if_missing "$NOTIFIED_IPS" "644"
create_file_if_missing "$LOCAL_LOG" "644"

if [ -s "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
  echo "[$(date)] Loaded config from $CONFIG_FILE"
else
  echo "[$(date)] Warning: Config file $CONFIG_FILE is empty or not found. Using fallback or environment variable."
  if [ -z "$WEBHOOK_URL" ]; then
    echo "[$(date)] Error: WEBHOOK_URL not set in environment or config file. Notifications may fail."
  fi
fi

for cmd in jq curl journalctl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "[$(date)] Error: $cmd is not installed. Exiting."
    exit 1
  fi
done

send_discord_notification() {
  local message="$1"
  echo "[$(date)] Notification to be sent:"
  echo "----------------------------------"
  echo -e "$message"
  echo "----------------------------------"
  echo "[$(date)] $message" >> "$LOCAL_LOG"

  if [ "$TEST_MODE" -eq 1 ]; then
    echo "[$(date)] Test mode: Skipping Discord webhook call."
    return
  fi

  if [ -z "$WEBHOOK_URL" ]; then
    echo "[$(date)] Error: WEBHOOK_URL is empty. Logging locally only."
    return
  fi

  local payload=$(jq -nc --arg username "$DISCORD_USERNAME" --arg avatar "$DISCORD_AVATAR" --arg content "$message" \
    '{username: $username, avatar_url: $avatar, content: $content}')
  if ! curl -s -H "Content-Type: application/json" -X POST -d "$payload" "$WEBHOOK_URL" > /dev/null; then
    echo "[$(date)] Error: Failed to send Discord notification. Logged locally."
  else
    echo "[$(date)] Discord notification sent successfully."
  fi
}

get_ip_info() {
  local ip="$1"
  local info=$(curl -s --connect-timeout 5 "http://ip-api.com/json/$ip")
  if [ $? -eq 0 ] && [ -n "$info" ]; then
    local status=$(echo "$info" | jq -r '.status')
    if [ "$status" == "success" ]; then
      local country=$(echo "$info" | jq -r '.country')
      local isp=$(echo "$info" | jq -r '.isp')
      echo "Country: $country, ISP: $isp"
    else
      local message=$(echo "$info" | jq -r '.message // "Unknown error"')
      echo "GeoIP Lookup Failed: $message"
    fi
  else
    echo "GeoIP Lookup Failed: Unable to connect to ip-api.com"
  fi
}


check_ip_notified() {
  local ip="$1"
  local cutoff=$(date -d "1 hour ago" +%s)
  if grep -q "$ip" "$NOTIFIED_IPS"; then
    last_notified=$(grep "$ip" "$NOTIFIED_IPS" | tail -n1 | awk '{print $2, $3, $4}')
    last_time=$(date -d "$last_notified" +%s 2>/dev/null || return 0)
    [ "$last_time" -ge "$cutoff" ] && return 1
  fi
  return 0
}

clean_old_logs() {
  local temp_file_new="/tmp/failed_attempts_new.log"
  local cutoff=$(date -d "1 hour ago" +%s)
  > "$temp_file_new"
  while IFS= read -r line; do
    timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
    log_time=$(date -d "$timestamp" +%s 2>/dev/null || continue)
    if [ "$log_time" -ge "$cutoff" ]; then
      echo "$line" >> "$temp_file_new"
    fi
  done < "$TEMP_FILE"
  mv "$temp_file_new" "$TEMP_FILE" 2>/dev/null || echo "[$(date)] Error: Failed to clean $TEMP_FILE"
}

check_logs() {
  echo "[$(date)] Checking logs for suspicious activity..."

  local ssh_failed=$(journalctl -u ssh.service --since "1 minute ago" | grep -Ei "Failed password|invalid user")
  local ssh_success=$(journalctl -u ssh.service --since "1 minute ago" | grep -Ei "Accepted password")
  local xfreerdp_failed=$(journalctl --since "1 minute ago" | grep -Ei "xfreerdp.*(failed|error|invalid)")

  clean_old_logs
  echo "[$(date)] Cleaned old logs in $TEMP_FILE"


  if [ -n "$ssh_success" ]; then
    echo "[$(date)] SSH successful login detected: $(echo "$ssh_success" | wc -l) entries"
    while read -r line; do
      ip=$(echo "$line" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
      user=$(echo "$line" | grep -oE "for [a-zA-Z0-9._-]+" | head -n1 | cut -d' ' -f2)
      timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
      if [ -n "$ip" ] && check_ip_notified "$ip"; then
        ip_info=$(get_ip_info "$ip")
        message="✅ SSH Login Successful 

        • IP Address: $ip  
        • Username: ${user:-Unknown}  
        • Login Time: $timestamp  

        Additional Info:  
        $ip_info"

        echo "[$(date)] Successful SSH login from IP: $ip, sending notification..."
        send_discord_notification "$message"
        echo "$ip $(date)" >> "$NOTIFIED_IPS"
      fi
    done <<< "$ssh_success"
  else
    echo "[$(date)] No successful SSH logins detected."
  fi



  if [ -n "$ssh_failed" ]; then
    echo "[$(date)] SSH failures detected: $(echo "$ssh_failed" | wc -l) entries"
    echo "$ssh_failed" >> "$TEMP_FILE"
    for ip in $(grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" "$TEMP_FILE" | sort | uniq); do
      count=$(grep -c "$ip" "$TEMP_FILE")
      user=$(grep "$ip" "$TEMP_FILE" | grep -oE "user [a-zA-Z0-9._-]+" | head -n1 | cut -d' ' -f2)
      timestamp=$(grep "$ip" "$TEMP_FILE" | tail -n1 | awk '{print $1, $2, $3}')
      echo "[$(date)] Processing IP: $ip, Attempts: $count"
      if [ "$count" -ge "$THRESHOLD" ] && check_ip_notified "$ip"; then
        ip_info=$(get_ip_info "$ip")
        message="🚨 SSH Attack Detected!

        ⚠️  IP Address: $ip  
        👤 User: ${user:-Unknown}  
        🔢 Attempt Count: $count  
        ⏰ Timestamp: $timestamp  

        $ip_info"

        echo "[$(date)] Threshold exceeded for IP: $ip, sending notification..."
        send_discord_notification "$message"
        echo "$ip $(date)" >> "$NOTIFIED_IPS"
        grep -v "$ip" "$TEMP_FILE" > "$TEMP_FILE.tmp" && mv "$TEMP_FILE.tmp" "$TEMP_FILE"
        echo "[$(date)] Cleared IP $ip from $TEMP_FILE"
      fi
    done
  else
    echo "[$(date)] No SSH failures detected."
  fi

  if [ -n "$xfreerdp_failed" ]; then
    echo "[$(date)] xFreeRDP failures detected: $(echo "$xfreerdp_failed" | wc -l) entries"
    while read -r line; do
      ip=$(echo "$line" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
      timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
      if [ -n "$ip" ] && check_ip_notified "$ip"; then
        ip_info=$(get_ip_info "$ip")
        message="⚠️ xFreeRDP Suspicious Activity Detected!

        🔹 IP Address: $ip  
        ⏰ Timestamp: $timestamp  

        $ip_info

        📋 Details:  
        \`\`\`  
        $line  
        \`\`\`"

        echo "[$(date)] xFreeRDP issue from IP: $ip, sending notification..."
        send_discord_notification "$message"
        echo "$ip $(date)" >> "$NOTIFIED_IPS"
      fi
    done <<< "$xfreerdp_failed"
  else
    echo "[$(date)] No xFreeRDP failures detected."
  fi
}

echo "[$(date)] Script started. Monitoring logs every $CHECK_INTERVAL seconds..."

while true; do
  check_logs
  echo "[$(date)] Sleeping for $CHECK_INTERVAL seconds..."
  sleep "$CHECK_INTERVAL"
done
