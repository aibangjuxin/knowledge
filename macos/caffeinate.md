# caffeinate

Prevent the system from sleeping on behalf of a utility.

## Syntax

```bash
caffeinate [-disu] [-t timeout] [-w Process ID] [command arguments...]
```

## Description

`caffeinate` creates assertions to alter system sleep behavior. If no assertion flags are specified, `caffeinate` creates an assertion to prevent idle sleep.

If a utility is specified, `caffeinate` creates the assertions on the utility's behalf, and those assertions will persist for the duration of the utility's execution.

Otherwise, `caffeinate` creates the assertions directly, and those assertions will persist until `caffeinate` exits.

## Options

| Flag | Description |
|------|-------------|
| `-d` | Create an assertion to prevent the **display** from sleeping. |
| `-i` | Create an assertion to prevent the system from **idle sleeping**. |
| `-m` | Create an assertion to prevent the **disk** from idle sleeping. |
| `-s` | Create an assertion to prevent the system from sleeping. **Only valid when running on AC power.** |
| `-u` | Declare that user is active. If the display is off, this option turns the display on and prevents it from going into idle sleep. Default timeout is 5 seconds if `-t` is not specified. |
| `-t timeout` | Specifies the timeout in **seconds** for which the assertion is valid. Not used when a utility is invoked. |
| `-w pid` | Waits for the process with the specified PID to exit. Once the process exits, the assertion is also released. Ignored when used with the utility option. |

## Examples

### Prevent idle sleep indefinitely (until process exits)

```bash
# Prevent system from idle sleeping
caffeinate -i

# Prevent system from sleeping (display + system), requires AC power
caffeinate -is

# Prevent idle sleep, display sleep, and disk sleep
caffeinate -ims
```

### Run a command and prevent sleep while it runs

```bash
# Run make and prevent idle sleep while building
caffeinate -i make

# Download a large file without sleeping
caffeinate -is curl -O large-file.iso
```

### Prevent sleep for a specific duration

```bash
# Prevent idle sleep for 1 hour
caffeinate -i -t 3600

# Prevent display sleep for 30 minutes
caffeinate -d -t 1800
```

### Wait for a process to finish

```bash
# Start a long-running process, get its PID, then caffeinate waits for it
./long-running-script.sh &
caffeinate -w $!
```

## Common Use Cases

| Scenario | Command |
|----------|---------|
| Keep Mac awake while presenting | `caffeinate -d` |
| Prevent sleep during file transfer | `caffeinate -is curl -O file.iso` |
| Keep awake indefinitely (CLI) | `caffeinate -ims` |
| Keep awake for 2 hours | `caffeinate -ims -t 7200` |
| Run a script without sleeping | `caffeinate -i ./script.sh` |

## How It Works

`caffeinate` uses the IOKit framework to create **power assertions** with the system. These assertions tell the kernel's power management that the system should remain awake for a specific reason.

When the assertion is released (process exits, timeout expires, or signal sent), the system can return to its normal power management behavior.

## Relationship with pmset

| Tool | Scope | Persistence |
|------|-------|-------------|
| `caffeinate` | Per-process assertions | Temporary, until process exits |
| `pmset` | System-wide power settings | Permanent (survives reboots with proper config) |

Use `pmset` for system-wide defaults and `caffeinate` for temporary, process-bound wakefulness.

## Notes

- `caffeinate` itself consumes **negligible CPU** — it just holds a kernel assertion
- On Apple Silicon Macs, `caffeinate` also prevents the Mac from sleeping while in standby
- Assertions can be verified with: `pmset -g live` (look for `sleep prevented by caffeinate`)
- Multiple `caffeinate` processes can run simultaneously; each holds its own assertion

## See Also

- `pmset(1)` — View and modify power management settings
- `pmutil(1)` — Manage power assertions

## Location

`/usr/bin/caffeinate`
