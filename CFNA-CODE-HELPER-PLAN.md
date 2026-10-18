# CFNA Email Code Helper — GrandmaOS Implementation Plan

Status: SPECIFICATION ONLY. No executable extension or native helper is currently bundled.
Primary deployment: fyne4247/grandmaOS, Linux Mint 22.3 XFCE (X11), Google Chrome.
Secondary browser: Firefox via a separate manifest/package and Mozilla native-messaging registration.
Primary provider: AOL Mail. Primary destination: CFNA (Credit First National Association).

## 1. User-facing goal

Grandma opens the real CFNA website, signs in normally, and reaches CFNA's email-verification prompt. She presses one large button labeled **Get verification code** on the CFNA page. The helper searches her authorized AOL inbox for a fresh CFNA message, waits for one if it has not arrived, then inserts the code into the appropriate CFNA field. It never clicks Continue, Pay, Submit, or similar buttons.

The page button is a requirement, NOT merely a nice-to-have: GrandmaOS launches sites as Chrome app-mode windows, which hide extension toolbar buttons. An extension toolbar entry is still available in standard browser windows. Provide a large, 200%-zoom-compatible CFNA page button with text and a clear, readable status: Checking AOL → Waiting for CFNA email → Code entered, or a specific failure.

No surveillance when the user is not waiting for a code. No server operated by this project. No telemetry, analytics, remotely hosted AI, or content transfers except the direct TLS connection to AOL and the user's existing CFNA web session.

## 2. Hardware and GrandmaOS constraints (verified from this repo)

- Linux Mint 22.3 XFCE on X11; main browser Google Chrome with enterprise policy.
- Dell XPS 13 (2026), Intel Core 5 Series 3 x86-64, 8 GB RAM, 512 GB NVMe, 13.4-inch 2.5K-class touchscreen. Exact device models may still need live verification.
- Grandma's user is 'grandma', has autologin, and is NOT an administrator.
- Chrome runs with 200% default zoom, larger fonts, one shared profile, app-mode dock windows, and force-controlled extensions. Existing ExtensionSettings blocks unknown extensions. Do not weaken the global blocklist.
- Chrome profile backup and browser-restart logic already exist. Never delete, reset, or replace her profile.
- Existing README/AGENTS.md forbid secrets in Git, stdout, shell history, logs, and unattended package removal. Respect these rules.
- Keep RAM/CPU use low. Prefer a short-lived Python 3 stdlib IMAP process invoked on demand; no Electron, browser automation framework, resident LLM, or always-on inbox process.

## 3. Scope and implementation order

P0: AOL Mail → CFNA in the managed Chrome profile, including the page button.
P1: Same local native host and parser in Firefox, with Firefox-specific manifest and signed/reviewed distribution.
P2: Generalize to other verified websites and providers (Gmail, Outlook), without making the CFNA reliability work depend on them.

Only authorize requested account access; never automate password entry, bank transactions, account changes, or OTP retrieval for other websites.

## 4. CFNA constraints / discovery

- CFNA's official customer support confirms identity-verification codes, potentially through email. Its site also describes phone/SMS verification in some circumstances. Email-only autofill cannot handle SMS.
- Identify the exact CFNA login hostname, redirects, email sender/domain, subject, code format, expiry, and HTML inputs from real owner-authorized use before locking production rules. Public CFNA pages alone do not prove these details.
- Allow HTTPS only and exact known CFNA origins, not arbitrary domains containing the letters 'cfna'. Redirects to third-party verification vendors require explicit verified allowlisting.
- Store trusted sender patterns only after inspecting genuine CFNA mail (without committing the messages); never assume a sender address.
- The extension must distinguish login email codes from password-reset, payment, and account-update codes.
- Test single OTP field, segmented inputs, auto-advance, paste/input events, iframes, SPA updates, 200% zoom, touchscreen, and the app-mode window.
- Refuse to autofill if the site, message, or target input is ambiguous. Display a readable error and an accessible copy-code fallback only for the currently authorized session.

## 5. Architecture

A. Browser extension:
- Chrome Manifest V3; Firefox-specific manifest as needed. Shared TypeScript logic for UI, session state, site matching, parser contract, and DOM filling.
- CFNA-only content script injects a large page button on the verification screen and never overlays a password field or ordinary navigation.
- Button click establishes a bounded scan session tied to the active tab, document identity, and exact HTTPS origin.
- Background code talks to the native helper using browser.runtime.connectNative. Validate message sender, tab, origin, session nonce, and requested capability before passing native messages.
- On a high-confidence match, fill the CFNA code input and dispatch appropriate native input/change events without submitting a form.
- Session canceled on navigation outside the allowlist, tab close, timeout, deliberate Cancel, or successful insertion.

B. Native messaging host:
- Python 3 with imaplib, email, ssl, secrets, time, and JSON framing; direct TLS connection to imap.aol.com:993, read-only mailbox access, no SMTP.
- Use IMAP UID / INTERNALDATE and a scan-start time gate. Immediately search a small recent window for a just-issued code, then poll every ~3–5 seconds up to 120 seconds by default (bounded retry, backoff on throttling).
- Decode MIME plain text and HTML; ignore attachments; set limits on fetched bodies and candidate count. No full-mailbox indexing.
- Compare timestamp, sender, subject, context, recipient, validity, and code structure. Return code only to the requesting authenticated extension context.
- A connectNative port lasts only for the user-initiated scanning window. No permanent daemon required for the baseline.
- Native host communicates only over length-prefixed JSON on stdin/stdout. Diagnostic output to stderr must be redacted.
- Install Chrome and Firefox manifests separately, each permitting only the appropriate stable extension ID.
- Do not open listening TCP ports, use a local HTTP server, or send email data to any project-controlled service.

## 6. AOL authorization / credentials

- AOL's official documentation supports IMAP access and explains account-specific app passwords for third-party apps. Use a dedicated AOL app password if AOL currently permits generating one.
- Account connection is a deliberate one-time owner/admin setup, not a first-login task for Grandma. Never ask Grandma to provide the main AOL password to a webpage extension.
- Secret never appears in browser extension storage, code, Git, provisioning output, environment exported to descendants, or shell history.
- Choose and test a machine-local protected storage mechanism compatible with GrandmaOS's passwordless LightDM autologin. A login keyring that stays locked after autologin is NOT sufficient.
- Compare Secret Service/libsecret with machine-bound systemd credential encryption or a narrowly permissioned installation before committing to a storage implementation; document the threat model, root/admin recovery path, and post-reboot access.
- Fail closed on authentication errors. Provide owner-facing reconnect / rotate-app-password instructions without logging the secret.

## 7. Security controls

- No host permissions beyond the verified CFNA HTTPS origins; AOL IMAP network traffic stays in the native helper, not fetch in arbitrary webpages.
- The extension cannot be directed by CFNA page JavaScript to retrieve arbitrary mail: action begins only with the extension's own trusted UI handler, and native requests are allowlisted.
- Do not accept an origin/host value from page DOM as authority. Validate against browser tab/document metadata.
- No wildcard native messaging callers. No automatic form submission. No saving OTP text in long-lived storage, diagnostics, or crash reports.
- Reject stale, previously used, mismatched, out-of-window, or multi-candidate codes. If the site sends a new code while one is being processed, prioritize fresh matching context without silently guessing.
- Bind a code to one session and consume/remove it from memory after fill or timeout.
- Timeouts and network errors leave the CFNA page usable and do not interfere with manual entry.

## 8. GrandmaOS installation and packaging

Source release layout (to be built later):

  files/cfna-code-helper/install-grandmaos.sh
  files/cfna-code-helper/native-host/...
  files/cfna-code-helper/extension/chrome/...
  files/cfna-code-helper/extension/firefox/...

The install-grandmaos.sh contract:
1. Accept --user grandma and --chrome-policy PATH, invoked as root from provision.sh.
2. Validate presence/checksums/signatures of a tested release bundle before changing anything.
3. Install the native helper root-owned and executable without embedding an AOL secret.
4. Install ONLY the Chrome native-message manifest with a real, stable Chrome extension ID and allowed_origins. Add Mozilla manifest with allowed_extensions only when Firefox is deployed.
5. Add the real Chrome extension to the existing ExtensionSettings policy, preserving every other key and extension entry. A force-install requires a valid release ID and compatible signed distribution/update URL; do not invent an ID, assume file:// policy support, or point the browser at a nonexistent CRX/update manifest.
6. Keep CFNA domain permissions narrow. Do not change the existing Better Text View exclusions for truist.com, AI-disabling policies, Safe Browsing, or blocking of unapproved extensions.
7. Install only after a validated extension distribution path is available and after the administrator completes AOL account setup.
8. Implement --dry-run, idempotence, full verification, error rollback, and read-only status diagnostics. Never reset Google Chrome, reinstall Linux, or overwrite the existing account.
9. Report not-installed / installed-unconfigured / connected / failed distinctly. Never report a plan or placeholder as a working installation.

provision.sh has a guarded phase that calls this installer ONLY if its executable exists. Until the app is implemented and a release is packaged, the provisioning phase is an explicit, safe no-op.

## 9. Manual setup and end-user UX

Owner-only commissioning:
1. Confirm the actual CFNA web flow and whether verification arrives by email.
2. Configure/test AOL IMAP authentication from Grandma's machine using an AOL app password (when supported).
3. Install a signed extension and local host; confirm managed Chrome policy and the native manifest.
4. Run a complete login test with a NEW CFNA code, on the real Dell at Grandma's display settings.
5. After reboot and Grandma's automatic login, repeat the test; this catches locked keyrings and missing access.
6. Show Grandma exactly one button: Get verification code. Provide Cancel and a large, actionable status/error label.

Expected flow:
- CFNA verification screen opens.
- User presses the visible page button.
- Status changes to Checking AOL, then Waiting for email if needed.
- Fresh, uniquely matched code arrives and fills; page remains ready for the user to continue.
- On SMS-only prompt, wrong sender, missing permission, ambiguous form, offline condition, or timeout, show the precise problem and leave the form untouched.

## 10. Tests / acceptance gates

- unit: IMAP MIME text/HTML and edge cases, CFNA subject/sender rules from owner-approved fixtures, one/multiple codes, stale messages, code lengths, UTF-8, missing email, UID replay, timeouts.
- extension: proper tab binding, navigation cancellations, spoofed messages, app-mode button visibility, iframe routing, single/segmented inputs, input/change events, no submit.
- native: correct length-prefixed transport, refusal of unknown IDs, no unauthenticated loopback network listener, TLS verification, reasonable IMAP retry/backoff, secret never logged.
- integration: Chrome Managed ExtensionSettings remains valid; other installed extensions still operate; no changes to Truist blocking; no profile corruption.
- human acceptance: on real Mint XFCE Dell, Grandma can complete CFNA's EMAIL verification with a single obvious button and no need to find AOL or copy digits; failure modes are readable and manual login remains possible.
- post-reboot: works after automatic login, Chrome app-mode site launch, and normal OS reboot/updates.

## 11. Exit conditions

Do not claim implementation complete until a signed tested extension exists, native host is installed, the AOL credential mechanism survives GrandmaOS autologin without insecure logging, the real CFNA email and input fields are validated, and a live user-authorized end-to-end CFNA flow succeeds.

References:
- CFNA support: https://www.cfna.com/customer-support
- AOL IMAP: https://help.aol.com/articles/how-do-i-use-other-email-applications-to-send-and-receive-my-aol-mail
- AOL app passwords: https://help.aol.com/articles/create-and-manage-app-password
- Chrome native messaging: https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
- Firefox native messaging: https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging
