---
name: eventful-setup
description: Build and install the eventful notification CLI (ntf) from source on macOS. Use when asked to set up, build, install, or repair eventful/ntf, or when ntf reports it is not authorized or not running inside its bundle.
---

# Setting up eventful

eventful is a macOS notification CLI. The binary `ntf` must live inside
`Eventful.app` (UserNotifications requires an app bundle) and be invoked via
the generated `build/ntf` exec wrapper — never symlink the binary directly.

## Steps

Run from the repository root.

1. **Certificate (one-time, recommended):**

   ```console
   $ scripts/make-cert.sh
   ```

   Expects a sudo password prompt for the trust settings. If it fails, tell
   the user to create it manually: Keychain Access.app > Certificate
   Assistant > Create a Certificate..., name `eventful-selfsigned`, type
   Code Signing. Ad-hoc signing works but may reset notification permission
   on every rebuild.

2. **Build, sign, register:**

   ```console
   $ scripts/build.sh
   ```

   Produces `build/Eventful.app` and the wrapper `build/ntf`, signs the
   bundle, and registers it with LaunchServices.

3. **Install on PATH:**

   ```console
   $ ln -sf "$(pwd)/build/ntf" ~/bin/ntf
   ```

4. **Permission and click-path verification (interactive):**

   ```console
   $ ntf setup
   ```

   This triggers the macOS notification permission prompt (the only code
   path that ever prompts) and posts a test notification. The human must
   click the prompt's Allow button and then click the test notification;
   setup waits up to 60s and confirms the click-to-execute path end to end.

## Verification and repair

- `ntf doctor` prints signature, permission status, and paths.
- If permission is `denied`, it cannot be re-prompted programmatically;
  the user must enable it in System Settings > Notifications > Eventful.
- Logs (click mode has no tty): `~/Library/Logs/eventful/ntf.log`.
