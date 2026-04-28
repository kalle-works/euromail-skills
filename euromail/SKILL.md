---
name: euromail
description: |
  Add euromail.dev transactional email to any project. Detects tech stack,
  installs SDK, configures auth, and writes integration code. Includes
  embeddable signup forms with CSS customization, and agent mailboxes with
  lease/ack/nack delivery, quote stripping, and intent classification.
  Use when: "add email", "send emails", "euromail",
  "transactional email", "integrate euromail", "signup form", "subscribe form",
  "agent mailbox", "inbound email for AI", "email for agent"
user_invocable: true
---

# euromail.dev Integration Skill

You are integrating euromail.dev — a GDPR-compliant transactional email API with EU data residency (Finland) — into the user's project.

> **For agents without the Claude Code skill system** (Cursor, Windsurf, Copilot, etc.):
> This file is the complete integration guide. Read it top to bottom and follow
> the workflow steps. All API reference, SDK examples, and gotchas are in the
> second half of this file. You do not need any special tooling — just follow
> the steps using your normal file editing and shell execution capabilities.

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
| `composer.json` | PHP |

If multiple are found, pick the primary one based on the project type (e.g. Rust project with a dashboard `package.json` → Rust). Only ask the user if the stack is genuinely ambiguous.

### Step 2: Install SDK

**TypeScript/Node.js** — official SDK:
```bash
npm install @euromail/sdk
```

**Rust** — official crate:
```toml
[dependencies]
euromail = "0.2"
```

**Python** — official package:
```bash
pip install euromail
```

**Go** — official module:
```bash
go get github.com/kalle-works/euromail-go
```

**PHP / other** — use raw HTTP with the language's native HTTP client.

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

Expected: `200`. If `401`, the key is invalid — ask the user to check it.

### Step 4: Add & Verify Sending Domain

**Auto-detect the domain in this order — stop at the first hit:**

1. Check existing verified domains on the account:
   ```bash
   curl -s https://api.euromail.dev/v1/domains \
     -H "Authorization: Bearer $EUROMAIL_API_KEY"
   ```
   If any domain has `verified: true`, use it — no further setup needed, skip to Step 5.

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

The API returns `dns_records` as a dict keyed by purpose (e.g. `dkim`, `return_path`), each with `type`, `host`, and `value` fields. Display them in a table:

| Type | Host | Value |
|------|------|-------|
| TXT | `euromail._domainkey.domain.com` | `v=DKIM1; k=rsa; p=...` |
| CNAME | `bounce.domain.com` | `bounce.euromail.dev` |

Also recommend they ensure their domain has:
- **SPF**: `v=spf1 include:spf.euromail.dev ~all` (or add `include:spf.euromail.dev` to existing SPF record)
- **DMARC**: `v=DMARC1; p=none; rua=mailto:dmarc@domain.com` (if they don't have one yet)

Tell the user: "Add these DNS records at your domain registrar, then tell me when done so I can verify."

**4d. Verify domain DNS** — once the user confirms records are added:

```bash
curl -s -X POST https://api.euromail.dev/v1/domains/{DOMAIN_ID}/verify \
  -H "Authorization: Bearer $EUROMAIL_API_KEY" | python3 -m json.tool
```

Show the verification results. If some checks fail, explain which records are missing and what to fix. DNS propagation can take minutes to hours — let the user know they can re-verify later.

If all critical checks pass (at minimum DKIM + return path), proceed to Step 5. If not, tell the user they can continue in sandbox mode (emails only delivered to account owner's email) and proceed anyway.

**Gotcha — From address is the apex, not the `em.` subdomain.** The DKIM / SPF / return-path records live on `em.their-domain.tld` (euromail's `sending_subdomain`), which looks like it should be the From domain. It isn't — that subdomain is infrastructure, not a registered sender domain. Sending with `from: "noreply@em.their-domain.tld"` returns `Domain 'em.their-domain.tld' is not registered for this account`. Always send from the apex (`from: "noreply@their-domain.tld"`), or from a different subdomain you've explicitly registered as its own euromail domain.

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

    let response = client.send_email(&SendEmailParams {
        from: "noreply@THEIR_DOMAIN".into(),
        to: "TEST_RECIPIENT".into(),
        subject: Some("euromail integration test".into()),
        html_body: Some("<h1>It works!</h1><p>Your euromail integration is live.</p>".into()),
        text_body: Some("It works! Your euromail integration is live.".into()),
        ..Default::default()
    }).await?;

    println!("Email sent! ID: {}, Status: {}", response.id, response.status);
    Ok(())
}
```

Run the script immediately. If it succeeds (202 response, status "queued"), the integration is complete.

If the domain is unverified (sandbox mode), the email will only be delivered to the account owner's address — inform the user about this.

### Step 6: Write Integration Code

Generate an email service module appropriate for the stack. Use the examples and API reference below. Place the file where it fits the project structure (e.g., `lib/email.ts`, `src/email.rs`, `utils/email.py`).

The module should include:
- Client initialization from environment variable
- A `sendEmail` / `send_email` function wrapping the SDK call
- Error handling for common API errors (401, 422, 429)

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
- Agent mailboxes (dedicated addresses for AI agents with lease/ack/nack delivery, intent classification, and threading). Two deployment shapes: bind the mailbox directly to the user's verified domain (`support@their-domain.tld`, clean, needs inbound MX on that domain — see Step 4e), or keep it on `@inbound.euromail.dev` and add an inbound route that forwards `something@their-domain.tld` → mailbox (no custom MX on the user's domain for the mailbox itself, but the *route*'s domain still needs MX). Prefer the first when practical.

Generate additional code as needed using the API reference below.

---

## Account defaults

- **Dashboard**: https://dashboard.euromail.dev
- **API keys**: https://dashboard.euromail.dev/api-keys
- **Default from**: `noreply@{verified-domain}` or `hello@{verified-domain}`
- **Sandbox mode**: Unverified domains can only deliver to the account owner's email address.
- **API key location hint**: Check `$EUROMAIL_API_KEY` env var, project `.env`, or `~/.zshrc` before asking.

---

## SDK Usage Examples

### TypeScript

```typescript
import { EuroMail } from "@euromail/sdk";

const euromail = new EuroMail({
  apiKey: process.env.EUROMAIL_API_KEY!,
});

// Send an email
const sent = await euromail.sendEmail({
  from: "noreply@yourdomain.com",
  to: "user@example.com",
  subject: "Welcome!",
  html_body: "<h1>Hello</h1><p>Welcome aboard.</p>",
});

console.log(sent.id);     // email ID
console.log(sent.status); // "queued"

// Send with a template
await euromail.sendEmail({
  from: "noreply@yourdomain.com",
  to: "user@example.com",
  template_alias: "welcome-email",
  template_data: { name: "Kalle", plan: "Pro" },
});

// Send batch (up to 500)
const batch = await euromail.sendBatch({
  emails: [
    { from: "noreply@yourdomain.com", to: "a@example.com", subject: "Hi A", text_body: "Hello A" },
    { from: "noreply@yourdomain.com", to: "b@example.com", subject: "Hi B", text_body: "Hello B" },
  ],
});

// Schedule for later
await euromail.sendEmail({
  from: "noreply@yourdomain.com",
  to: "user@example.com",
  subject: "Reminder",
  text_body: "Don't forget!",
  send_at: "2026-04-01T09:00:00Z",
});

// Get email detail (includes events)
const detail = await euromail.getEmail(sent.id);
console.log(detail.email.status, detail.events.length);

// List emails
const emails = await euromail.listEmails({ page: 1, per_page: 25 });

// Cancel a scheduled email
await euromail.cancelScheduledEmail(sent.id);

// Broadcast to a contact list
await euromail.sendBroadcast({
  contact_list_id: "list-uuid",
  from_address: "noreply@yourdomain.com",
  subject: "Weekly Update",
  html_body: "<p>News this week...</p>",
});

// Templates
const template = await euromail.createTemplate({
  alias: "welcome",
  name: "Welcome Email",
  subject: "Welcome {{ name }}!",
  html_body: "<p>Hello {{ name }}, welcome to {{ company }}!</p>",
});

// Domains — dns_records is a dict keyed by purpose (dkim, return_path, etc.)
const domain = await euromail.addDomain("yourdomain.com");
console.log(domain.dns_records.dkim.host);  // "euromail._domainkey.yourdomain.com"

// Verify domain — returns checks per record type
const verification = await euromail.verifyDomain(domain.id);
console.log(verification.checks.spf?.verified);  // true/false

// Tracking domain
await euromail.setTrackingDomain(domain.id, "track.yourdomain.com");
const trackCheck = await euromail.verifyTrackingDomain(domain.id);
console.log(trackCheck.tracking_check.verified);

// Webhooks — secret returned only on create, store it securely
const webhook = await euromail.createWebhook({
  url: "https://yourapp.com/webhooks/euromail",
  events: ["delivered", "bounced", "complained"],
});
console.log(webhook.secret); // store this for signature verification

// Contact lists
const list = await euromail.createContactList({ name: "Newsletter" });
await euromail.addContact(list.id, { email: "user@example.com" });

// Analytics
const stats = await euromail.getAnalyticsOverview({ period: "30d" });

// Validate email
const validation = await euromail.validateEmail("test@example.com");
console.log(validation.valid, validation.deliverable); // true, "yes"

// API keys
const key = await euromail.createApiKey({ name: "my-app", scopes: ["emails:send"] });
console.log(key.key); // store securely, only shown once

// Signup Forms
const signupForm = await euromail.createSignupForm({
  list_id: list.id,
  title: "Subscribe to updates",
  description: "Weekly news delivered to your inbox.",
  custom_fields: [
    { name: "first_name", label: "First Name", type: "text", required: true }
  ],
  messages: {
    submit_button: "Tilaa",
    email_label: "Sähköpostiosoite",
    already_subscribed: "Olet jo tilannut tämän listan.",
  },
});
console.log(signupForm.form_url);    // public URL
console.log(signupForm.embed_code);  // iframe HTML

// Toggle form active/inactive
await euromail.toggleSignupForm(signupForm.id);

// Newsletters
const nl = await euromail.createNewsletter({
  list_id: list.id,
  subject: "Monthly Update",
  from_address: "news@yourdomain.com",
  html_body: "<p>This month...</p>",
});
await euromail.sendNewsletter(nl.id);

// Operations — track async operations (broadcasts, newsletter sends)
const ops = await euromail.listOperations({ page: 1, per_page: 10 });

// Billing
const plans = await euromail.listPlans();
const sub = await euromail.getSubscription();

// Agent Mailboxes — dedicated email addresses for AI agents
const mailbox = await euromail.createAgentMailbox({
  local_part: "support-bot",
  display_name: "Support Agent",
});
console.log(mailbox.address); // "support-bot@mail.euromail.dev"

// Long-poll for next message (blocks until a message arrives or timeout)
const next = await euromail.getNextMailboxMessage(mailbox.id, { timeout_secs: 30 });
if (next) {
  console.log(next.message.subject);
  console.log(next.message.text_body_stripped); // quoted history removed
  console.log(next.message.classification);     // { label: "question", confidence: 0.89 }
  console.log(next.message.thread_id);          // correlate replies into conversations

  // Process the message, then ack to remove from queue
  await euromail.ackMailboxMessage(mailbox.id, next.message.id, next.lease_token);
}

// Reply with thread tracking (sets In-Reply-To / References)
await euromail.replyToMailboxMessage(mailbox.id, next.message.id, {
  html_body: "<p>Thanks for reaching out! Here's your answer...</p>",
  text_body: "Thanks for reaching out! Here's your answer...",
});

// Search messages
const results = await euromail.searchMailboxMessages(mailbox.id, { q: "invoice" });

// List threads
const threads = await euromail.listMailboxThreads(mailbox.id);
```

### Rust

```rust
use euromail::{EuroMail, SendEmailParams};

let client = EuroMail::new(std::env::var("EUROMAIL_API_KEY").unwrap());

// Send email — returns SendEmailResponse directly
let response = client.send_email(&SendEmailParams {
    from: "noreply@yourdomain.com".into(),
    to: "user@example.com".into(),
    subject: Some("Welcome!".into()),
    html_body: Some("<h1>Hello</h1>".into()),
    ..Default::default()
}).await?;

println!("Email ID: {}", response.id);

// Domains — dns_records is HashMap<String, DnsRecord> with .host field
let domain = client.add_domain("yourdomain.com").await?;
if let Some(dkim) = domain.dns_records.get("dkim") {
    println!("DKIM host: {}", dkim.host);
}

// Verify domain — returns DomainVerificationResult
let result = client.verify_domain(&domain.id).await?;
if let Some(spf) = result.checks.get("spf") {
    println!("SPF verified: {}, detail: {}", spf.verified, spf.detail);
}

// Validate email
let v = client.validate_email("test@example.com").await?;
println!("Valid: {}, deliverable: {}", v.valid, v.deliverable);
```

### Python

```python
import os
from euromail import EuroMail

client = EuroMail(api_key=os.environ["EUROMAIL_API_KEY"])

# Send email — returns SendEmailResponse dataclass
response = client.send_email(
    from_address="noreply@yourdomain.com",
    to="user@example.com",
    subject="Welcome!",
    html_body="<h1>Hello</h1><p>Welcome aboard.</p>",
)
print(response.id, response.status)  # uuid, "queued"

# Domains — dns_records is dict[str, DnsRecord] with .host field
domain = client.add_domain("yourdomain.com")
print(domain.dns_records["dkim"].host)

# Verify domain — returns DomainVerificationResult
result = client.verify_domain(domain.id)
spf = result.checks.get("spf")
if spf:
    print(f"SPF: {spf.verified} — {spf.detail}")

# Validate email
v = client.validate_email("test@example.com")
print(v.valid, v.deliverable)
```

### Go

```go
package main

import (
    "context"
    "fmt"
    "os"
    euromail "github.com/kalle-works/euromail-go"
)

func main() {
    client := euromail.NewClient(os.Getenv("EUROMAIL_API_KEY"))
    ctx := context.Background()

    // Send email
    resp, err := client.SendEmail(ctx, euromail.SendEmailParams{
        From:     "noreply@yourdomain.com",
        To:       "user@example.com",
        Subject:  euromail.String("Welcome!"),
        HTMLBody: euromail.String("<h1>Hello</h1>"),
    })
    if err != nil { panic(err) }
    fmt.Println(resp.ID, resp.Status)

    // Domains — DnsRecords is map[string]DnsRecord with .Host field
    domain, _ := client.AddDomain(ctx, "yourdomain.com")
    fmt.Println(domain.DnsRecords["dkim"].Host)

    // Verify domain — returns DomainVerificationResult
    result, _ := client.VerifyDomain(ctx, domain.ID)
    if spf, ok := result.Checks["spf"]; ok {
        fmt.Println(spf.Verified, spf.Detail)
    }

    // Validate email
    v, _ := client.ValidateEmail(ctx, "test@example.com")
    fmt.Println(v.Valid, v.Deliverable)
}
```

### Raw HTTP (any language)

```bash
curl -X POST https://api.euromail.dev/v1/emails \
  -H "Authorization: Bearer em_live_your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "from": "noreply@yourdomain.com",
    "to": "user@example.com",
    "subject": "Hello",
    "html_body": "<p>Hello world</p>"
  }'
```

---

## Webhook Signature Verification

Webhooks are signed with HMAC-SHA256. The secret is returned only at webhook creation — store it securely.

**Header format**: `X-Euromail-Signature: t={unix_timestamp},v1={hex_signature}`

**Additional headers**:
- `X-Euromail-Event`: Event type (`sent`, `delivered`, `bounced`, `opened`, `clicked`, `complained`, `email.inbound`)
- `X-Euromail-Attempt`: Retry attempt (1–5)

**Verification algorithm**:
1. Parse `t` (timestamp) and `v1` (signature) from header.
2. Reject if timestamp is older than 5 minutes (replay protection).
3. Compute: `HMAC-SHA256(secret, "{timestamp}.{raw_request_body}")`.
4. Compare hex digest to `v1` using constant-time comparison.

### TypeScript verification example

```typescript
import { createHmac, timingSafeEqual } from "crypto";

function verifyWebhook(secret: string, signatureHeader: string, body: string): boolean {
  const parts = Object.fromEntries(
    signatureHeader.split(",").map((p) => p.split("=") as [string, string])
  );
  const timestamp = parts.t;
  const signature = parts.v1;

  // Replay protection (5 min)
  if (Math.abs(Date.now() / 1000 - Number(timestamp)) > 300) return false;

  const expected = createHmac("sha256", secret)
    .update(`${timestamp}.${body}`)
    .digest("hex");

  return timingSafeEqual(Buffer.from(signature), Buffer.from(expected));
}
```

### Python verification example

```python
import hmac, hashlib, time

def verify_webhook(secret: str, signature_header: str, body: str) -> bool:
    parts = dict(pair.split("=", 1) for pair in signature_header.split(","))
    timestamp = parts["t"]
    signature = parts["v1"]

    if abs(time.time() - int(timestamp)) > 300:
        return False

    expected = hmac.new(
        secret.encode(), f"{timestamp}.{body}".encode(), hashlib.sha256
    ).hexdigest()

    return hmac.compare_digest(signature, expected)
```

---

## Complete API Reference

**Base URL**: `https://api.euromail.dev`
**Auth header**: `X-EuroMail-Api-Key: em_live_...` (also supports `Authorization: Bearer <key>`)
**Content-Type**: `application/json`

### Emails

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/emails` | Send single email |
| `POST` | `/v1/emails/batch` | Send batch (up to 500) |
| `POST` | `/v1/emails/broadcast` | Broadcast to contact list |
| `GET` | `/v1/emails` | List emails (paginated) |
| `GET` | `/v1/emails/{id}` | Get email details + events |
| `POST` | `/v1/emails/{id}/cancel` | Cancel scheduled email |

**Send email request body**:
```json
{
  "from": "sender@yourdomain.com",
  "to": "recipient@example.com",
  "cc": [],
  "bcc": [],
  "reply_to": "reply@yourdomain.com",
  "subject": "Subject line",
  "html_body": "<p>HTML content</p>",
  "text_body": "Plain text fallback",
  "template_alias": "welcome-email",
  "template_data": { "name": "Kalle" },
  "headers": { "X-Custom": "value" },
  "tags": ["onboarding"],
  "metadata": { "user_id": "123" },
  "attachments": [
    {
      "filename": "report.pdf",
      "content_type": "application/pdf",
      "content": "base64-encoded-content"
    }
  ],
  "idempotency_key": "unique-key-123",
  "send_at": "2026-04-01T09:00:00Z"
}
```

Required: `from`, `to`. Must provide `subject` + (`html_body` or `text_body`), or `template_alias`.

**Send email response** (202 Accepted):
```json
{
  "data": {
    "id": "uuid",
    "message_id": "<uuid@euromail.dev>",
    "status": "queued",
    "to": "recipient@example.com",
    "sandbox": false,
    "scheduled_at": null,
    "created_at": "2026-03-29T10:00:00Z"
  }
}
```

**Get email response** — returns nested email + events:
```json
{
  "data": {
    "email": { "id": "...", "from_address": "...", "to_address": "...", "status": "..." },
    "events": [{ "event_type": "sent", "created_at": "..." }]
  }
}
```

### Templates (MiniJinja syntax)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/templates` | Create template |
| `GET` | `/v1/templates` | List templates |
| `GET` | `/v1/templates/{id}` | Get template |
| `PUT` | `/v1/templates/{id}` | Update template |
| `DELETE` | `/v1/templates/{id}` | Delete template |

Template syntax uses **MiniJinja** (Jinja2-compatible): `{{ variable }}`, `{% if %}`, `{% for %}`, `{{ value | upper }}`.

### Domains

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/domains` | Add domain |
| `GET` | `/v1/domains` | List domains |
| `GET` | `/v1/domains/{id}` | Get domain + DNS records |
| `POST` | `/v1/domains/{id}/verify` | Verify DNS (SPF, DKIM, DMARC, return path, MX) |
| `DELETE` | `/v1/domains/{id}` | Delete domain |
| `PUT` | `/v1/domains/{id}/tracking-domain` | Set vanity tracking domain |
| `POST` | `/v1/domains/{id}/verify-tracking` | Verify tracking CNAME |
| `DELETE` | `/v1/domains/{id}/tracking-domain` | Remove tracking domain |

### Webhooks

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/webhooks` | Create webhook (returns secret) |
| `GET` | `/v1/webhooks` | List webhooks |
| `GET` | `/v1/webhooks/{id}` | Get webhook |
| `PUT` | `/v1/webhooks/{id}` | Update webhook |
| `DELETE` | `/v1/webhooks/{id}` | Delete webhook |
| `POST` | `/v1/webhooks/{id}/test` | Send test event (5/min limit) |

**Events**: `sent`, `delivered`, `bounced`, `opened`, `clicked`, `complained`, `email.inbound`, `mailbox.message.received`

### Suppressions

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/suppressions` | Add suppression |
| `GET` | `/v1/suppressions` | List suppressions |
| `DELETE` | `/v1/suppressions/{email}` | Remove suppression |

### Contact Lists

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/contact-lists` | Create list |
| `GET` | `/v1/contact-lists` | List all |
| `GET` | `/v1/contact-lists/{id}` | Get list |
| `PUT` | `/v1/contact-lists/{id}` | Update list |
| `DELETE` | `/v1/contact-lists/{id}` | Delete list |
| `POST` | `/v1/contact-lists/{id}/contacts` | Add contacts |
| `GET` | `/v1/contact-lists/{id}/contacts` | List contacts |
| `DELETE` | `/v1/contact-lists/{id}/contacts/{email}` | Remove contact |

### Signup Forms

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/signup-forms` | Create signup form for a contact list |
| `GET` | `/v1/signup-forms` | List all signup forms |
| `GET` | `/v1/signup-forms/{id}` | Get signup form details |
| `PUT` | `/v1/signup-forms/{id}` | Update signup form |
| `DELETE` | `/v1/signup-forms/{id}` | Delete signup form |
| `POST` | `/v1/signup-forms/{id}/toggle` | Toggle active/inactive |

**Create signup form request body**:
```json
{
  "list_id": "contact-list-uuid",
  "title": "Subscribe to our newsletter",
  "description": "Get weekly updates delivered to your inbox.",
  "success_message": "Thank you for subscribing!",
  "redirect_url": "https://yoursite.com/thank-you",
  "custom_fields": [
    { "name": "first_name", "label": "First Name", "type": "text", "required": true }
  ],
  "messages": {
    "submit_button": "Tilaa",
    "email_label": "Sähköpostiosoite",
    "email_placeholder": "sinun@esimerkki.fi",
    "submitting": "Lähetetään…",
    "already_subscribed": "Olet jo tilannut tämän listan.",
    "confirmation_sent": "Lähetimme vahvistussähköpostin.",
    "confirmation_pending": "Vahvistussähköposti on jo lähetetty.",
    "invalid_email": "Syötä kelvollinen sähköpostiosoite.",
    "error": "Jokin meni pieleen. Yritä uudelleen."
  }
}
```

Required: `list_id`, `title`. Scope: `contacts:manage`.

The `messages` field allows full localization of all form UI text. Omit any key to use the English default. The embed.js widget includes minimal default styles that work out-of-the-box.

**Response** includes computed fields:
```json
{
  "data": {
    "id": "uuid",
    "slug": "newsletter-a1b2c3",
    "form_url": "https://api.euromail.dev/subscribe/newsletter-a1b2c3",
    "embed_code": "<iframe src=\"...\" ...></iframe>",
    "is_active": true,
    ...
  }
}
```

#### Public subscribe endpoints (no auth required)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/subscribe/{slug}` | Render standalone signup form page |
| `POST` | `/subscribe/{slug}` | Submit subscription (form or JSON) |
| `GET` | `/subscribe/{slug}/embed.js` | JavaScript embed widget |
| `GET` | `/confirm/{token}` | Confirm double opt-in subscription |

#### Embeddable JavaScript widget

The recommended way to embed a signup form is with the JS widget. It renders directly in the customer's DOM so their own CSS applies:

```html
<div id="euromail-form"></div>
<script src="https://api.euromail.dev/subscribe/{slug}/embed.js"></script>
```

**CSS classes for styling** (all prefixed `em-` to avoid collisions):

| Class | Element |
|-------|---------|
| `.em-form` | Form wrapper |
| `.em-form__title` | h2 title |
| `.em-form__description` | Description paragraph |
| `.em-form__field` | Field wrapper (label + input) |
| `.em-form__label` | Input label |
| `.em-form__input` | Text/email input |
| `.em-form__button` | Submit button |
| `.em-form__message` | Success/error message |
| `.em-form__message--success` | Success state |
| `.em-form__message--error` | Error state |
| `.em-form__powered` | "Powered by EuroMail" link |

Example styling:
```css
.em-form__input {
  border: 1px solid #333;
  border-radius: 4px;
  padding: 0.75rem;
  font-size: 1rem;
}
.em-form__button {
  background: #0d9488;
  color: white;
  border-radius: 4px;
}
```

The widget submits via `fetch()` with JSON responses — no page reload.

### Analytics

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/analytics/overview` | Summary stats |
| `GET` | `/v1/analytics/timeseries` | Daily timeseries |
| `GET` | `/v1/analytics/domains` | Stats by recipient domain |
| `GET` | `/v1/analytics/export` | Export CSV |

Query params: `period` (`7d`, `30d`, `90d`), `from` (YYYY-MM-DD), `to` (YYYY-MM-DD).

### Inbound Emails

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/inbound` | List inbound emails |
| `GET` | `/v1/inbound/{id}` | Get inbound email |
| `DELETE` | `/v1/inbound/{id}` | Delete inbound email |

### Inbound Routes

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/inbound-routes` | Create route |
| `GET` | `/v1/inbound-routes` | List routes |
| `GET` | `/v1/inbound-routes/{id}` | Get route |
| `PUT` | `/v1/inbound-routes/{id}` | Update route |
| `DELETE` | `/v1/inbound-routes/{id}` | Delete route |

**Create request body**:
```json
{
  "domain_id": "uuid-of-euromail-domain",
  "pattern": "support@",
  "match_type": "exact",
  "action": "mailbox",
  "mailbox_id": "uuid-of-agent-mailbox"
}
```

Exact-match patterns must end with `@` (e.g. `"support@"` matches `support@<domain>`) — a bare local part like `"support"` fails validation with "Exact match pattern must end with '@'". The domain must have `mx_verified = true` before you can create routes on it.

**When to use an inbound route vs. a domain-bound agent mailbox**: if the goal is just "deliver `foo@user-domain.tld` into a mailbox queue," create the mailbox directly with `domain_id` set to that verified domain — no route needed. Use a route when you want many addresses to fan into one mailbox, forward to a webhook, or keep the mailbox on `@inbound.euromail.dev` while presenting a vanity address on the user's domain.

**Route deletion note**: deleting a mailbox does not cascade to routes targeting it. Delete routes first, then the mailbox, or `GET /v1/inbound-routes` and clean up dangling `mailbox_id`s afterwards.

### Agent Mailboxes

Agent mailboxes give each AI agent or workflow a dedicated email address. By default the address is `<local_part>@inbound.euromail.dev`; pass `domain_id` pointing at a domain with `mx_verified = true` and `inbound_enabled = true` to bind the mailbox to the user's own domain instead (`<local_part>@their-domain.tld`). Inbound replies land in a queue with at-least-once delivery via lease/ack/nack. Each message is automatically classified by intent (interested, question, unsubscribe, etc.) when the account has an Anthropic API key configured at `/settings/integrations`.

**Create request body**:
```json
{
  "local_part": "support",
  "domain_id": "uuid-of-verified-domain",
  "display_name": "Support Agent"
}
```

The only valid domain field is `domain_id` (a UUID). A plain string `domain` is accepted but silently ignored — the returned mailbox still lives on `inbound.euromail.dev`. `address` is also silently ignored — the server generates `mb-<hex>@inbound.euromail.dev`. If `domain_id` points at a domain whose MX is not verified yet, the API returns `Domain must have MX verified and inbound enabled` — fix the DNS first, then retry.

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/agent-mailboxes` | Create mailbox |
| `GET` | `/v1/agent-mailboxes` | List mailboxes |
| `GET` | `/v1/agent-mailboxes/{id}` | Get mailbox |
| `DELETE` | `/v1/agent-mailboxes/{id}` | Delete mailbox |
| `GET` | `/v1/agent-mailboxes/{id}/messages/next` | Long-poll next message (leases it) |
| `POST` | `/v1/agent-mailboxes/{id}/messages/{msg}/ack` | Acknowledge |
| `POST` | `/v1/agent-mailboxes/{id}/messages/{msg}/nack` | Return to queue |
| `GET` | `/v1/agent-mailboxes/{id}/messages` | List messages (?status=all\|unread\|read) |
| `DELETE` | `/v1/agent-mailboxes/{id}/messages/{msg}` | Delete message |
| `POST` | `/v1/agent-mailboxes/{id}/messages/{msg}/reply` | Reply with thread tracking |
| `GET` | `/v1/agent-mailboxes/{id}/messages/{msg}/attachments` | Pre-signed download URLs |
| `PUT` | `/v1/agent-mailboxes/{id}/messages/{msg}/labels` | Set labels |
| `GET` | `/v1/agent-mailboxes/{id}/messages/search` | Full-text search |
| `GET` | `/v1/agent-mailboxes/{id}/threads` | List threads |
| `GET` | `/v1/agent-mailboxes/{id}/threads/{tid}` | Thread messages |
| `GET` | `/v1/agent-mailboxes/{id}/contacts` | Unique contacts |
| `GET` | `/v1/agent-mailboxes/{id}/analytics` | Summary stats |
| `PATCH` | `/v1/agent-mailboxes/{id}/auto-responder` | Configure auto-responder |

**Lease/ack flow** — long-poll returns one message with a `lease_token` (5 min TTL). Process the message, then ack. If your worker crashes, the lease expires and the message becomes available again. Nack returns it immediately.

**`mailbox.message.received` webhook payload**:
```json
{
  "event": "mailbox.message.received",
  "mailbox_id": "uuid",
  "message": {
    "id": "uuid",
    "from": "Alice <alice@example.com>",
    "reply_to": null,
    "subject": "Re: Help with my order",
    "text_body": "Thanks, that worked!\n\nOn Mon...",
    "text_body_stripped": "Thanks, that worked!",
    "html_body": "<p>Thanks, that worked!</p>...",
    "attachments": [],
    "message_id": "<abc@example.com>",
    "in_reply_to": "<def@euromail.dev>",
    "references": "<def@euromail.dev> <ghi@euromail.dev>",
    "thread_id": "uuid",
    "classification": { "label": "interested", "confidence": 0.92 },
    "received_at": "2026-04-15T10:01:23Z"
  },
  "source_ip": "1.2.3.4",
  "timestamp": "2026-04-15T10:01:24Z"
}
```

`text_body_stripped` strips quoted reply history (attribution lines, >-blocks, signatures). `classification` is null when the account has no Anthropic key configured. Both are opt-in — they appear as extra fields alongside the full body.

**Webhook payload vs. REST list/get — field names differ.** The webhook uses friendly names (`from`, `received_at`, `classification.label`); the REST message resource returned from `/v1/agent-mailboxes/{id}/messages` and related endpoints uses `from_header`, `created_at`, and flat `classification` / `classification_confidence`. Readers that poll the REST API must map:

| Webhook field | REST field |
|---------------|------------|
| `from` | `from_header` (also `mail_from` for envelope sender) |
| `received_at` | `created_at` |
| `classification.label` + `classification.confidence` | `classification` (string) + `classification_confidence` (float) |

Bodies (`text_body`, `text_body_stripped`, `html_body`) and threading fields (`thread_id`, `in_reply_to`, `references_header`) keep the same names in both.

### Email Validation

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/validate` | Validate email (syntax, MX, disposable, role, free provider) |

### Sub-Accounts

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/accounts` | Create sub-account |
| `GET` | `/v1/accounts` | List sub-accounts |
| `GET` | `/v1/accounts/{id}` | Get sub-account |
| `PATCH` | `/v1/accounts/{id}` | Update sub-account |
| `DELETE` | `/v1/accounts/{id}` | Delete sub-account |
| `GET` | `/v1/accounts/{id}/analytics` | Sub-account analytics |
| `POST` | `/v1/accounts/{id}/api-keys` | Create sub-account API key |

### API Keys

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/api-keys` | Create API key |
| `GET` | `/v1/api-keys` | List API keys |
| `DELETE` | `/v1/api-keys/{id}` | Delete API key |

**Valid scopes**: `emails:send`, `emails:read`, `emails:validate`, `domains:manage`, `templates:manage`, `webhooks:manage`, `contacts:manage`, `account:admin`, `sub_accounts:manage`. Omit scopes for full access.

### Account & GDPR

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/account` | Get account details |
| `DELETE` | `/v1/account` | Delete account (GDPR) |
| `GET` | `/v1/account/export` | Export all data (GDPR) |

### Newsletters

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/newsletters` | Create newsletter |
| `GET` | `/v1/newsletters` | List newsletters |
| `GET` | `/v1/newsletters/{id}` | Get newsletter |
| `PUT` | `/v1/newsletters/{id}` | Update newsletter |
| `DELETE` | `/v1/newsletters/{id}` | Delete newsletter |
| `POST` | `/v1/newsletters/{id}/send` | Send newsletter |

### Operations

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/operations` | List async operations |
| `GET` | `/v1/operations/{id}` | Get operation status |

### GDPR (per-email)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/gdpr/export?email={email}` | Export all data for an email address |
| `DELETE` | `/v1/gdpr/erase?email={email}` | Erase all data for an email address |

### Audit Logs

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/audit-logs` | List audit logs |

### Dead Letters

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/dead-letters` | List dead letters |
| `POST` | `/v1/dead-letters/{id}/retry` | Retry dead letter |
| `DELETE` | `/v1/dead-letters/{id}` | Delete dead letter |

### Billing

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/billing/plans` | List plans (public) |
| `GET` | `/v1/billing/subscription` | Get subscription |
| `POST` | `/v1/billing/checkout` | Create Stripe checkout |
| `POST` | `/v1/billing/portal` | Create Stripe portal |

---

## Limits & Constraints

| Constraint | Value |
|------------|-------|
| Max request body | 2 MB |
| Max html_body / text_body | 256 KB each |
| Max subject | 998 characters |
| Max recipients (TO+CC+BCC) | 50 per email |
| Max tags | 10 per email, 256 chars each |
| Max attachments | 10 per email |
| Max attachment size | 10 MB per file |
| Max total attachments | 25 MB |
| Max batch size | 500 emails |
| Max scheduled ahead | 30 days |
| Blocked attachment types | .exe, .bat, .cmd, .scr, .com, .msi, .js, .vbs, .ws, .ps1 |
| Idempotency key max length | 255 characters |
| Template alias | alphanumeric + hyphens/underscores, max 100 chars |
| Pagination default | 25 per page |
| Pagination max | 100 per page |

### Rate Limits

| Scope | Limit |
|-------|-------|
| Global | 500 req/s |
| Per account | 50 req/s |
| New accounts (first 7 days) | 50/min, 500/hour |
| After 7 days | 200/min, 2000/hour |
| Webhook tests | 5/min per webhook |

**Rate limit headers**: `x-ratelimit-limit`, `x-ratelimit-remaining`, `retry-after` (on 429).

---

## Error Responses

```json
{
  "error": {
    "type": "validation_error",
    "code": "VALIDATION_ERROR",
    "message": "Invalid 'from' address: not-an-email"
  }
}
```

| HTTP | Type | Code |
|------|------|------|
| 401 | `unauthorized` | `UNAUTHORIZED` |
| 403 | `forbidden` | `FORBIDDEN` |
| 403 | `permission_error` | `INSUFFICIENT_SCOPE` |
| 404 | `not_found` | `NOT_FOUND` |
| 409 | `conflict` | `CONFLICT` |
| 422 | `validation_error` | `VALIDATION_ERROR` |
| 429 | `rate_limited` | `RATE_LIMIT_EXCEEDED` |
| 429 | `quota_exceeded` | `QUOTA_EXCEEDED` |
| 500 | `internal_error` | `INTERNAL_ERROR` |

Batch responses include partial success:
```json
{
  "operation_id": "uuid",
  "data": [ /* successful emails */ ],
  "errors": [
    { "index": 2, "error": "Invalid email address" }
  ]
}
```
