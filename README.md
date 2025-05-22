# The Watcher - Security Monitoring Script

`the_watcher.sh` is a Bash script designed to monitor system logs for suspicious activities, such as failed SSH login attempts, successful SSH logins, and xFreeRDP errors. It sends notifications to a Discord channel via a webhook when specific thresholds or events are detected. The script also performs GeoIP lookups to provide additional context about the source of detected activities.

## Features
- Monitors SSH (`ssh.service`) and xFreeRDP logs using `journalctl`.
- Tracks failed login attempts and detects when they exceed a configurable threshold.
- Notifies about successful SSH logins and xFreeRDP errors.
- Sends formatted alerts to a Discord channel using a webhook.
- Performs GeoIP lookups for IP addresses using the `ip-api.com` service.
- Maintains a local log of alerts and temporary logs of failed attempts.
- Supports a test mode (`--test`) to simulate notifications without sending them.
- Cleans up old logs to prevent excessive disk usage.

## Requirements
- **Dependencies**: `jq`, `curl`, `journalctl` (must be installed).
- **Permissions**: The script must have read access to system logs (e.g., `/var/log`) and write access to temporary files (e.g., `/tmp`, `/var/log`).
- **Discord Webhook**: A valid Discord webhook URL for sending notifications.

## Configuration
The script uses the following configuration files and variables:

### Files
- `/etc/watcher.conf`: Configuration file for storing variables like `WEBHOOK_URL`.
- `/tmp/failed_attempts.log`: Temporary storage for failed login attempts.
- `/tmp/notified_ips.log`: Tracks IPs that have been notified to avoid duplicate alerts within an hour.
- `/var/log/security_alerts.log`: Local log for all notifications.

### Variables
- `CONFIG_FILE`: Path to the configuration file (`/etc/watcher.conf`).
- `TEMP_FILE`: Path to the temporary log for failed attempts (`/tmp/failed_attempts.log`).
- `NOTIFIED_IPS`: Path to the file tracking notified IPs (`/tmp/notified_ips.log`).
- `LOCAL_LOG`: Path to the local security log (`/var/log/security_alerts.log`).
- `THRESHOLD`: Number of failed login attempts to trigger a notification (default: `10`).
- `CHECK_INTERVAL`: Interval (in seconds) between log checks (default: `10`).
- `DISCORD_USERNAME`: Username for Discord notifications (`the_watcher.sh`).
- `DISCORD_AVATAR`: URL for the Discord avatar.
- `WEBHOOK_URL`: Discord webhook URL for sending notifications.
- `TEST_MODE`: Set to `1` when running with `--test` flag to disable webhook calls.

### Example `config`
```bash
WEBHOOK_URL="https://discord.com/api/webhooks/your_webhook_url_here"
