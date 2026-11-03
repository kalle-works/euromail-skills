---
name: euromail
description: |
  Add euromail.dev transactional email to any project. Detects tech stack,
  installs SDK, configures auth, and writes integration code. Also covers SMTP
  sending, the MCP server, signup forms, and agent mailboxes with
  lease/ack/nack delivery, quote stripping, intent classification and spam
  verdicts.
  Use when: "add email", "send emails", "euromail",
  "transactional email", "integrate euromail", "signup form", "subscribe form",
  "agent mailbox", "inbound email for AI", "email for agent", "euromail smtp",
  "euromail mcp"
user-invocable: true
---

# euromail.dev Integration Skill

You are integrating euromail.dev — a GDPR-compliant transactional email API with EU data residency (Finland) — into the user's project.

> **For agents without the Claude Code skill system** (Cursor, Windsurf, Copilot, etc.):
> Read this file top to bottom and follow the workflow steps. SDK examples, limits and
> gotchas are in the second half, and it says where the full API reference is served.
> You need no special tooling, only your normal file editing and shell commands.

## Autonomy principles

**Detect before asking.** At each step, exhaust all auto-detection options before prompting the user. The happy path should require zero user input. Only block on user input when the information is genuinely unavailable from the environment, files, or API.

**Default test recipient**: Detect from the environment in this order — stop at the first hit:
1. Git config: `git config user.email`
2. `package.json` → `author.email` or `"author"` string
3. `pyproject.toml` → `[project] authors`
4. Ask the user: "What email should I send the test email to?"

Never hardcode an email address. Always resolve it at runtime.

## Workflow

This skill performs a complete end-to-end setup. Follow every step — do not skip ahead.

### Step 1: Detect Tech Stack

Check the project root for these files to determine the stack:

| File | Stack |
|------|-------|
| `package.json` | Node.js / TypeScript |
| `Cargo.toml` | Rust |
| `requirements.txt` or `pyproject.toml` | Python |
| `go.mod` | Go |
| `wp-config.php`, `wp-load.php`, or a `wp-content/` directory | WordPress |
| `composer.json` | PHP |

If multiple are found, pick the primary one based on the project type (e.g. Rust project with a dashboard `package.json` → Rust). WordPress takes priority over the generic PHP row — a WordPress install gets the official plugin (Step 2), not the raw SDK, even if it also has a `composer.json`. Only ask the user if the stack is genuinely ambiguous.

If the thing that sends mail only has SMTP settings (a CMS, a device, a framework's mailer the user wants to keep), use the SMTP section further down instead of an SDK. Steps 3 to 5 still apply.

### Step 2: Install SDK

**TypeScript/Node.js** — official SDK:
```bash
npm install @euromail/sdk
```

**Rust** — official crate:
```toml
[dependencies]
euromail = "0.8"
```

**Python** — official package:
```bash
pip install euromail
```

**Go** — official module:
```bash
go get github.com/kalle-works/euromail-go
```

**PHP** — official package via Composer:
```bash
composer require euromail/euromail:^1.0
```
No `composer.json` in the project? Fall back to raw HTTP with PHP's native HTTP client.

**WordPress** — do not install the SDK directly. Install the official Euromail plugin instead: search "Euromail" under Plugins → Add New in wp-admin if it's live on wordpress.org yet, otherwise install the latest release zip from `https://github.com/kalle-works/euromail-wordpress/releases` (Plugins → Add New → Upload Plugin, or extract into `wp-content/plugins/`). Activate it, then go to **Euromail → Settings** and paste the API key (or define `EUROMAIL_API_KEY` in `wp-config.php`) — this covers Step 3 below. Every `wp_mail()` call — password resets, WooCommerce orders, form notifications — now routes through EuroMail automatically, so there is no integration code to write (skip Step 6). Domain verification (Step 4) still applies — an unverified domain sandboxes every send — and the plugin's own **Euromail → Send Test** page covers Step 5.

**Other languages** — use raw HTTP with the language's native HTTP client.

### Step 3: Setup API Key

**Auto-detect in this order — stop at the first hit:**

1. Shell environment: `echo $EUROMAIL_API_KEY`
2. Project `.env` file: `grep EUROMAIL_API_KEY .env 2>/dev/null`
3. Project `.env.local`: `grep EUROMAIL_API_KEY .env.local 2>/dev/null`
4. Shell profile: `grep EUROMAIL_API_KEY ~/.zshrc ~/.zprofile ~/.bashrc ~/.bash_profile 2>/dev/null | head -1`
5. Global config file: `cat ~/.config/euromail/api_key 2>/dev/null`

If found anywhere **other than** the project `.env`, add it to `.env` so the project has a local copy.

If not found anywhere, ask the user:

> I couldn't find `EUROMAIL_API_KEY` in your environment or project files. Create one at https://dashboard.euromail.dev/api-keys and paste it here, or set `EUROMAIL_API_KEY=em_live_...` in your shell and re-run.

Once you have the key:

1. Add `EUROMAIL_API_KEY` to `.env` (create if missing, or add to existing):
   ```
   EUROMAIL_API_KEY=em_live_...
   ```
2. Add `.env` to `.gitignore` if not already there.
3. If `.env.example` exists, add `EUROMAIL_API_KEY=` (no value) there too.

**Verify the key works:**

```bash
curl -s -o /dev/null -w "%{http_code}" https://api.euromail.dev/v1/account \
  -H "Authorization: Bearer $EUROMAIL_API_KEY"
```

- `200`: the key works and has full access.
- `403` with code `INSUFFICIENT_SCOPE`: the key works but lacks `account:admin`. That is normal for a scoped key. The domain steps below need `domains:manage`, and the test send needs `emails:send`.
- `401`: read `error.code`. `AUTH_MISSING` means nothing was sent, `AUTH_MALFORMED` means it isn't a key (the placeholder `em_live_...` counts), and `AUTH_INVALID_KEY` means it is mistyped or deleted. Ask the user to check it.

### Step 4: Add & Verify Sending Domain

**Auto-detect the domain in this order — stop at the first hit:**

1. Check existing verified domains on the account:
   ```bash
   curl -s https://api.euromail.dev/v1/domains \
     -H "Authorization: Bearer $EUROMAIL_API_KEY"
   ```
   A domain whose `verified_at` is set is verified. Use it, no further setup needed, and skip to Step 5. Domains have no `verified` field.

2. Infer from `package.json` → `homepage` field (e.g. `https://app.example.com` → `example.com`)

3. Infer from git remote URL:
   ```bash
   git remote get-url origin 2>/dev/null
   ```
   Extract apex domain from SSH or HTTPS remote (e.g. `git@github.com:acme/app.git` → look for a related domain, not github.com itself).

4. Check the project `.env` for any `DOMAIN`, `APP_URL`, `NEXT_PUBLIC_URL`, `BASE_URL`, or `SITE_URL` vars.

5. If none found, ask the user: "Which domain do you want to send emails from?"

Once you have the domain, proceed:

**4a. Check existing domains** — list domains to see if it's already added:

```bash
curl -s https://api.euromail.dev/v1/domains \
  -H "Authorization: Bearer $EUROMAIL_API_KEY" | python3 -m json.tool
```

If the domain already exists, skip to 4c.

**4b. Add the domain** via the API:

```bash
curl -s -X POST https://api.euromail.dev/v1/domains \
  -H "Authorization: Bearer $EUROMAIL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"domain": "THEIR_DOMAIN"}' | python3 -m json.tool
```

Save the returned domain `id` and `dns_records` from the response.

**4c. Show DNS records** — present the required DNS records clearly to the user:

The API returns `dns_records` as a dict keyed by purpose (`dkim`, `spf`, `return_path`, `dmarc`), each with `type`, `host` and `value`. Show the values from the response, not from memory. They look like this:

| Purpose | Type | Host | Value |
|---------|------|------|-------|
| `dkim` | TXT | `euromail._domainkey.em.domain.com` | `v=DKIM1; k=rsa; p=...` |
| `spf` | TXT | `em.domain.com` | `v=spf1 include:spf.euromail.dev ~all` |
| `return_path` | MX, priority 10 | `em.domain.com` | `bounce.euromail.dev` |
| `dmarc` | TXT | `_dmarc.domain.com` | `v=DMARC1; p=none; rua=mailto:dmarc@euromail.dev` |

Everything except DMARC sits under the `em.` subdomain, so the domain's existing SPF and MX records stay as they are. If the domain already has a DMARC record, keep it rather than adding a second one.

Tell the user: "Add these DNS records at your domain registrar, then tell me when done so I can verify."

**4d. Verify domain DNS** — once the user confirms records are added:

```bash
curl -s -X POST https://api.euromail.dev/v1/domains/{DOMAIN_ID}/verify \
  -H "Authorization: Bearer $EUROMAIL_API_KEY" | python3 -m json.tool
```

Show the verification results. If some checks fail, explain which records are missing and what to fix. DNS propagation can take minutes to hours — let the user know they can re-verify later.

If all critical checks pass (at minimum DKIM + return path), proceed to Step 5. If not, tell the user they can continue in sandbox mode (emails only delivered to account owner's email) and proceed anyway.

**Gotcha — From address is the apex, not the `em.` subdomain.** The DKIM / SPF / return-path records live on `em.their-domain.tld` (euromail's `sending_subdomain`), which looks like it should be the From domain. It isn't — that subdomain is infrastructure, not a registered sender domain. Sending with `from: "noreply@em.their-domain.tld"` returns `403 SENDER_DOMAIN_NOT_REGISTERED`. Always send from the apex (`from: "noreply@their-domain.tld"`), or from a different subdomain you've explicitly registered as its own euromail domain.

**4e. (Optional) Enable inbound mail on the domain** — skip unless the user wants to *receive* mail at `user@their-domain.tld` (agent mailboxes bound to the domain, inbound routes, `/v1/inbound`). The send-side DNS from 4a-4d does *not* enable inbound: it only sets up DKIM / SPF / bounce return-path, which is a different MX on a sending subdomain (e.g. `em.their-domain.tld`).

Inbound needs a separate MX record on the address's domain (apex or whatever subdomain you want mail for):

| Type | Host | Priority | Value |
|------|------|----------|-------|
| MX | the address's domain | 10 | `mail1.euromail.dev.` |
| MX | the address's domain | 20 | `mail2.euromail.dev.` |

Warn the user: adding MX on the apex catches *all* `@their-domain.tld` inbound. If their team already receives mail at that domain (Google Workspace, Fastmail, etc.), use an inbound subdomain (`mail.their-domain.tld`, `inbound.their-domain.tld`) instead and register that as a separate euromail domain.

After publishing, re-verify with the same `/v1/domains/{id}/verify` call. On success `mx_verified` flips to `true` and mailboxes / routes on that domain become available.

### Step 5: Send Test Email

Send a test email to verify the full pipeline works. Use the SDK (not curl) to validate the integration code works end-to-end.

**Test recipient**: Resolve from the environment before writing the script:
1. `git config user.email`
2. `package.json` → `author.email` (or parse the `"author"` string)
3. `pyproject.toml` → `[project] authors`
4. If none found, ask the user: "What email should I send the test to?"

Write a small test script appropriate for the stack and run it (substitute the resolved email for `TEST_RECIPIENT`):

**TypeScript** — create `scripts/test-email.ts` (or `.js`):
```typescript
import { EuroMail } from "@euromail/sdk";

const euromail = new EuroMail({ apiKey: process.env.EUROMAIL_API_KEY! });

const result = await euromail.sendEmail({
  from: "noreply@THEIR_DOMAIN",
  to: "TEST_RECIPIENT",
  subject: "euromail integration test",
  html_body: "<h1>It works!</h1><p>Your euromail integration is live.</p>",
  text_body: "It works! Your euromail integration is live.",
});

console.log(`Email sent! ID: ${result.id}, Status: ${result.status}`);
```

**Python** — create `scripts/test_email.py`:
```python
import os
from euromail import EuroMail

client = EuroMail(api_key=os.environ["EUROMAIL_API_KEY"])

response = client.send_email(
    from_address="noreply@THEIR_DOMAIN",
    to="TEST_RECIPIENT",
    subject="euromail integration test",
    html_body="<h1>It works!</h1><p>Your euromail integration is live.</p>",
    text_body="It works! Your euromail integration is live.",
)

print(f"Email sent! ID: {response.id}, Status: {response.status}")
```

**Rust** — create `examples/test_email.rs`:
```rust
use euromail::{EuroMail, SendEmailParams};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = EuroMail::new(std::env::var("EUROMAIL_API_KEY")?);

    let response = client
        .send_email(
            &SendEmailParams::new("noreply@THEIR_DOMAIN", "TEST_RECIPIENT")
                .subject("euromail integration test")
                .html_body("<h1>It works!</h1><p>Your euromail integration is live.</p>")
                .text_body("It works! Your euromail integration is live."),
        )
        .await?;

    println!("Email sent! ID: {}, Status: {}", response.id, response.status);
    Ok(())
}
```

Run the script immediately. If it succeeds (202 response, status "queued"), the integration is complete.

If the domain is unverified (sandbox mode, `"sandbox": true` in the response), the email is only delivered to the account owner's address. Tell the user. A test to any other address fails with `VALIDATION_ERROR` until the domain is verified.

### Step 6: Write Integration Code

Generate an email service module appropriate for the stack. Use the examples and API reference below. Place the file where it fits the project structure (e.g., `lib/email.ts`, `src/email.rs`, `utils/email.py`).

The module should include:
- Client initialization from environment variable
- A `sendEmail` / `send_email` function wrapping the SDK call
- Error handling that branches on `error.code`, not on the message: fix-the-request errors (`VALIDATION_ERROR`, `RECIPIENT_SUPPRESSED`, `SENDER_DOMAIN_NOT_REGISTERED`) must not be retried, and `RATE_LIMIT_EXCEEDED` and `QUOTA_EXCEEDED` wait for `retry-after`. The Errors section has the table.
- An `idempotency_key` on sends a caller might retry, so a retry cannot send twice.

### Step 7: Cleanup & Next Steps

1. Delete the test email script (or keep it if the user wants).
2. Show the user a summary of what was set up:
   - SDK installed
   - API key configured in `.env`
   - Domain added (and verification status)
   - Test email sent successfully
   - Integration module created at `path/to/email.{ts,py,rs}`

Then ask if they need:
- Email templates
- Webhook receiver for delivery events
- Contact list management
- Signup forms (embeddable subscribe forms)
- Email validation
- Analytics integration
- Inbound email handling (basic routes + webhooks)
- The MCP server, so an assistant can send and manage email itself
- Agent mailboxes (dedicated addresses for AI agents with lease/ack/nack delivery, intent classification, and threading). Two deployment shapes: bind the mailbox directly to the user's verified domain (`support@their-domain.tld`, clean, needs inbound MX on that domain — see Step 4e), or keep it on `@inbound.euromail.dev` and add an inbound route that forwards `something@their-domain.tld` → mailbox (no custom MX on the user's domain for the mailbox itself, but the *route*'s domain still needs MX). Prefer the first when practical.

Generate additional code as needed using the API reference below.

---

## Account defaults

- **Dashboard**: https://dashboard.euromail.dev
- **API keys**: https://dashboard.euromail.dev/api-keys
- **Default from**: `noreply@{verified-domain}` or `hello@{verified-domain}`
- **Sandbox mode**: an unverified domain can only deliver to the account owner's address. The send response says so with `"sandbox": true`.
- **A new account starts small**: 20 recipients in its first 24 hours, refilling at 2 an hour, and 3,000 a month until an invoice has been paid. A `429` here is the limit working, not a bug. Rate limits are below.

---

## API reference

This file holds the workflow and what is easy to get wrong. The route list lives with the API, so read it from there instead of from memory:

| What | Where |
|------|-------|
| Every route, generated from the server | `https://api.euromail.dev/api-docs/openapi.json` |
| The reference as one text file | `https://api.euromail.dev/llms-full.txt` |
| Guides, per feature | `https://euromail.dev/docs/guides/` |

List the routes of one area, for example agent mailboxes:

```bash
curl -s https://api.euromail.dev/api-docs/openapi.json \
  | python3 -c "import json,sys; [print(' '.join(sorted(m.upper() for m in v)), p) for p,v in json.load(sys.stdin)['paths'].items() if 'agent-mailboxes' in p]"
```

**Auth**: `Authorization: Bearer em_live_...` (`X-EuroMail-Api-Key` also works). **Base URL**: `https://api.euromail.dev`.

---

## SDK usage

The examples below are compile-checked against the versions in Step 2. For anything else, each SDK follows the API's operations, so look up the route, then the method in the SDK's types.

### TypeScript

```typescript
import { EuroMail, verifyWebhookSignature } from "@euromail/sdk";

const euromail = new EuroMail({ apiKey: process.env.EUROMAIL_API_KEY! });

// Send
const sent = await euromail.sendEmail({
  from: "noreply@yourdomain.com",
  to: "user@example.com",
  subject: "Welcome!",
  html_body: "<h1>Hello</h1><p>Welcome aboard.</p>",
  text_body: "Hello. Welcome aboard.",
});
console.log(sent.id, sent.status); // "queued"

// Send with a template
await euromail.sendEmail({
  from: "noreply@yourdomain.com",
  to: "user@example.com",
  template_alias: "welcome-email",
  template_data: { name: "Ada", plan: "Pro" },
});

// Batch, up to 500
await euromail.sendBatch({
  emails: [
    { from: "noreply@yourdomain.com", to: "a@example.com", subject: "Hi A", text_body: "Hello A" },
    { from: "noreply@yourdomain.com", to: "b@example.com", subject: "Hi B", text_body: "Hello B" },
  ],
});

// Schedule, up to 30 days ahead, and cancel
const later = await euromail.sendEmail({
  from: "noreply@yourdomain.com",
  to: "user@example.com",
  subject: "Reminder",
  text_body: "Don't forget!",
  send_at: "2030-04-01T09:00:00Z",
});
await euromail.cancelScheduledEmail(later.id);

// Domain: dns_records is keyed by purpose (dkim, spf, return_path, dmarc)
const domain = await euromail.addDomain("yourdomain.com");
const verification = await euromail.verifyDomain(domain.id);

// Webhook: the secret comes back only on create, so store it
const webhook = await euromail.createWebhook({
  url: "https://yourapp.com/webhooks/euromail",
  events: ["sent", "bounced", "complained"],
});
console.log(webhook.secret);

// Verify a delivery against the raw body, before parsing it
function isGenuine(rawBody: string, header: string | null, secret: string): boolean {
  return verifyWebhookSignature(rawBody, header, secret);
}

// Agent mailbox: lease a message, work on it, then ack
const mailbox = await euromail.createMailbox({ local_part: "support-bot", display_name: "Support Agent" });
console.log(mailbox.address); // support-bot@inbound.euromail.dev

const next = await euromail.waitForNextMessage(mailbox.id);
if (next) {
  console.log(next.data.subject, next.data.classification);
  await euromail.replyToMessage(mailbox.id, next.data.id, { text_body: "Thanks, here is your answer." });
  await euromail.ackMessage(mailbox.id, next.data.id, next.lease_token);
}
```

### Rust

`SendEmailParams` is `#[non_exhaustive]`, so build it with `new` and the setters. A struct literal with `..Default::default()` does not compile.

```rust
use euromail::{EuroMail, SendEmailParams};

let client = EuroMail::from_env(); // reads EUROMAIL_API_KEY, panics if unset

let response = client
    .send_email(
        &SendEmailParams::new("noreply@yourdomain.com", "user@example.com")
            .subject("Welcome!")
            .html_body("<h1>Hello</h1>")
            .text_body("Hello"),
    )
    .await?;
println!("{} {}", response.id, response.status);

let domain = client.add_domain("yourdomain.com").await?;
let result = client.verify_domain(&domain.id).await?;
```

Verify a webhook with `euromail::verify_webhook_signature(body, header, secret)?`.

### Python

```python
import os
from euromail import EuroMail, verify_signature

client = EuroMail(api_key=os.environ["EUROMAIL_API_KEY"])

# Note from_address, not from
response = client.send_email(
    from_address="noreply@yourdomain.com",
    to="user@example.com",
    subject="Welcome!",
    html_body="<h1>Hello</h1>",
    text_body="Hello",
)
print(response.id, response.status)

domain = client.add_domain("yourdomain.com")
result = client.verify_domain(domain.id)

# Verify a webhook against the raw body bytes
def is_genuine(raw_body: bytes, header: str, secret: str) -> bool:
    return verify_signature(raw_body, header, secret)
```

### Go

```go
client := euromail.NewClient(os.Getenv("EUROMAIL_API_KEY"))
ctx := context.Background()

resp, err := client.SendEmail(ctx, euromail.SendEmailParams{
	From:     "noreply@yourdomain.com",
	To:       euromail.ToRecipient("user@example.com"),
	Subject:  euromail.String("Welcome!"),
	HTMLBody: euromail.String("<h1>Hello</h1>"),
	TextBody: euromail.String("Hello"),
})
```

Verify a webhook with `euromail.VerifyWebhookSignature(payload, header, secret)`.

### PHP

The client is `EuroMail\Client`; see `https://euromail.dev/docs/guides/sdks/` for its calls. Retries are off unless you pass `max_retries`.

### Raw HTTP

```bash
curl -X POST https://api.euromail.dev/v1/emails \
  -H "Authorization: Bearer $EUROMAIL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "from": "noreply@yourdomain.com",
    "to": "user@example.com",
    "subject": "Hello",
    "html_body": "<p>Hello world</p>",
    "text_body": "Hello world"
  }'
```

Send the idempotency key as the `idempotency_key` body field; an `Idempotency-Key` header is not read.

### SMTP

Use SMTP for anything that has SMTP settings and no code to change. It goes through the same pipeline as the API.

| Setting | Value |
|---------|-------|
| Host | `smtp.euromail.dev` |
| Port | `587` (STARTTLS) or `465` (TLS) |
| Username | `apikey`, the literal word |
| Password | an API key with the `emails:send` scope |

### MCP server

Use this to let an assistant send and manage email itself rather than writing integration code. It needs Node.js 22 or newer.

```bash
claude mcp add euromail --env EUROMAIL_API_KEY=em_live_your_key_here -- npx -y @euromail/mcp-server
```

---

## Webhooks

**Events**: `sent`, `deferred`, `bounced`, `failed`, `opened`, `clicked`, `complained`, `email.inbound`, `mailbox.message.received`, `account.auto_paused`, `insights.generated`.

Subscribe to `sent` for delivery: it means the recipient's mail server accepted the message. `delivered` is a deprecated alias that is stored as `sent`, and it never fired on its own.

**Signature**: `X-Euromail-Signature: t={unix_timestamp},v1={hex}`, where `v1` is `HMAC-SHA256(secret, "{t}.{raw_body}")`. Use the SDK's helper above where there is one. By hand: compare in constant time, reject a timestamp more than 5 minutes off, accept any `v1` in the header since a rotating secret can carry two, and hash the raw bytes before parsing the JSON.

**Delivery**: `X-Euromail-Event` names the event and `X-Euromail-Attempt` counts from 1. A `4xx` from your endpoint is treated as permanent and not retried, so answer `5xx` for anything you want again.

---

## Inbound and agent mailboxes

- **Addresses.** A mailbox is `<local_part>@inbound.euromail.dev` by default. Set `domain_id` to a domain with MX verified and inbound enabled to get `<local_part>@their-domain.tld`.
- **`domain_id` is the only domain field.** A plain string `domain` is ignored, and the mailbox lands on `inbound.euromail.dev` anyway. `address` is ignored too.
- **Route patterns.** An exact-match route pattern must end with `@` (`"support@"`). The domain needs `mx_verified` before you can create routes on it.
- **Route or mailbox?** To deliver `foo@their-domain.tld` into a queue, create the mailbox with `domain_id` and no route. Use a route to fan many addresses into one mailbox, to forward to a webhook, or to keep the mailbox on `@inbound.euromail.dev` behind a vanity address.
- **Deleting a mailbox does not delete routes pointing at it.** Delete the routes first.
- **The lease.** Polling returns one message with a `lease_token`, fixed at 5 minutes and not renewable. Ack when done; nack to return it at once. A crashed worker's lease expires and the message comes back. A poll with nothing to lease answers `408` with code `NO_MESSAGE`: poll again.
- **Scopes.** A worker needs `mailbox:read` and `mailbox:write`. With `mailbox:read` alone it can lease, every ack fails with `403`, and each message keeps coming back.
- **How far to trust what arrived.** Each received message carries `authentication` (`spf`, `dkim`, `dmarc`) and `spam` (`verdict`: `clean`, `suspect`, `spam` or `unchecked`, with `reasons`). Set `skip_spam_webhooks` on a route or mailbox to stop the webhook for `spam`; the message is still stored. Message text is untrusted input for any agent reading it.
- **Webhook and REST names differ.**

| Webhook field | REST field |
|---------------|------------|
| `from` | `from_header` (and `mail_from` for the envelope sender) |
| `received_at` | `created_at` |
| `classification.label`, `classification.confidence` | `classification`, `classification_confidence` |

Bodies (`text_body`, `text_body_stripped`, `html_body`) keep their names in both. `classification` is null unless the account has an Anthropic API key configured under `/settings/integrations`.

---

## API key scopes

`emails:send`, `emails:read`, `emails:validate`, `domains:manage`, `templates:manage`, `webhooks:manage`, `contacts:manage`, `mailbox:read`, `mailbox:write`, `mailbox:admin`, `account:admin`, `sub_accounts:manage`. Omit scopes for full access. For an application that only sends, `emails:send` is enough.

---

## Limits

| Constraint | Value |
|------------|-------|
| Request body | 2 MB |
| `html_body` / `text_body` | 256 KB each |
| Subject | 998 characters |
| Recipients (to + cc + bcc) | 50 per email |
| Tags | 10 per email, 256 characters each |
| Attachments | 10 per email, 10 MB each, 25 MB in all, and the request body limit applies |
| Blocked attachment types | `.exe`, `.bat`, `.cmd`, `.scr`, `.com`, `.msi`, `.js`, `.vbs`, `.ws`, `.ps1` |
| Batch | 500 emails |
| Scheduled ahead | 30 days |
| Idempotency key | 255 characters |
| Template alias | letters, digits, hyphens and underscores, 100 characters |
| Pagination | 25 per page by default, 100 at most |

Every attachment is also scanned for viruses. A refused one rejects the whole send with `ATTACHMENT_REFUSED`, and a scanner that cannot answer gives `503 ATTACHMENT_SCAN_UNAVAILABLE` with `retry-after`: retry the whole request.

### Rate limits

| Limit | Value |
|-------|-------|
| Whole API | 500 requests a second |
| Per account | 50 requests a second |
| Send rate, first 24 hours | 5 emails a minute, 25 an hour |
| Send rate, days 2 to 7 | 15 a minute, 75 an hour |
| Send rate, from day 8 | 100 a minute, 500 an hour |
| Send rate, once a paid invoice has settled | a tenth of the plan's monthly allowance per hour, a tenth of that per minute |
| New-account allowance | 20 recipients, refilling at 2 an hour, for the first 24 hours (1,000 once an invoice is paid) |
| Monthly allowance | the plan's volume; 3,000 until a non-zero invoice has been paid |
| Webhook tests | 5 a minute per webhook |

Sandbox sends skip the send rate and the new-account allowance. In a batch, an email refused by these limits is listed in `errors` and `rate_limited` with `retry_after_seconds`, and the rest of the batch goes through.

---

## Errors

```json
{
  "error": {
    "type": "validation_error",
    "code": "VALIDATION_ERROR",
    "message": "Invalid 'from' address: not-an-email"
  }
}
```

Branch on `code`: it is stable. `message` is for people and can change. Some errors add `docs_url`. The full table with retry advice is at `https://euromail.dev/docs/guides/errors-and-rate-limits/`.

| HTTP | `code` | Do |
|------|--------|----|
| 401 | `AUTH_MISSING`, `AUTH_MALFORMED`, `AUTH_INVALID_KEY` | Fix the key. The placeholder `em_live_...` is `AUTH_MALFORMED`. |
| 403 | `INSUFFICIENT_SCOPE` | Use a key with the scope the message names. |
| 403 | `SENDER_DOMAIN_NOT_REGISTERED` | Add the `from` domain. A subdomain is a separate domain. |
| 403 | `ACCOUNT_SUSPENDED`, `ACCOUNT_UNDER_REVIEW`, `CARD_VERIFICATION_REQUIRED` | Tell the user. Retrying will not help. |
| 408 | `NO_MESSAGE` | Mailbox long poll: poll again. |
| 409 | `CONFLICT` | It already exists. |
| 422 | `VALIDATION_ERROR` | Fix the request. This is also how an unverified domain sending to someone else is refused. |
| 422 | `RECIPIENT_SUPPRESSED` | The address bounced, complained or unsubscribed. Do not retry; the body has `reason`. |
| 422 | `ATTACHMENT_REFUSED` | Blocked type or failed scan. Nothing was sent. |
| 429 | `RATE_LIMIT_EXCEEDED`, `QUOTA_EXCEEDED` | Wait for `retry-after`. |
| 500, 503 | `INTERNAL_ERROR`, `SERVICE_UNAVAILABLE`, `ATTACHMENT_SCAN_UNAVAILABLE` | Retry with backoff. |
