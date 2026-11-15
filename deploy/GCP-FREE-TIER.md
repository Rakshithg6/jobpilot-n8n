# Running JobPilot on Google Cloud (uses your $300 credit)

You do not need Oracle. Your Google Cloud account can host JobPilot, but there
are two limits worth understanding before you start, because they decide
whether this stays free.

## Read this first: what the $300 actually is

| Fact | What it means for you |
|---|---|
| $300 credit is valid **90 days** | Large VMs are free *during the trial*, not after it |
| Free Trial accounts can be closed | If you never upgrade, after 90 days (or when the credit is spent) resources are **stopped**, then deleted after a 30-day grace period |
| The **Free Tier** is separate and has no end date | One `e2-micro` VM in `us-west1`, `us-central1` or `us-east1` + 30 GB standard disk is free **forever** |

So the practical choice is:

- **Free forever (recommended for JobPilot):** `e2-micro`, 1 GB RAM, tuned.
  Costs $0 now and $0 after the trial, as long as you stay inside the free tier.
- **Comfortable now, costs later:** `e2-small` (2 GB) runs on credit for the
  trial, then bills roughly $13/month once the credit expires.

JobPilot is a very light workload: a handful of HTTP calls every 6-12 hours, one
digest a day, one email poll. It does not need a big machine. Measured on your
own laptop with your real data:

```
n8n       417 MB
postgres   65 MB
```

That is about 480 MB, so a 1 GB VM works with swap and a little tuning. This
guide uses `e2-micro` and shows exactly how to tune it.

---

## Part 1 - Create the VM

1. Open <https://console.cloud.google.com> and make sure the correct project is
   selected at the top.
2. **Compute Engine -> VM instances -> Create instance**.
   If asked, click **Enable** for the Compute Engine API and wait a minute.
3. Name: `jobpilot`
4. **Region:** `us-central1` (Iowa). Only `us-west1`, `us-central1` and
   `us-east1` are free tier. Zone: any, e.g. `us-central1-a`.
5. **Machine configuration -> Series: E2 -> Machine type: `e2-micro`**
   (2 shared vCPU, 1 GB memory). This is the free tier shape.
6. **OS and storage -> Change**
   - Operating system: **Ubuntu**
   - Version: **Ubuntu 24.04 LTS x86/64**
   - Boot disk type: **Standard persistent disk**
   - Size: **30 GB** (the free allowance)
7. **Firewall:** tick **Allow SSH traffic**. Leave HTTP/HTTPS unticked - n8n is
   reached through an SSH tunnel, not a public port.
8. Leave everything else default. Click **Create**.
9. Wait for the green tick, then copy the **External IP**.

### Reserve that IP so it never changes

Ephemeral IPs change on stop/start. A static IP is free while it is attached to a
running VM.

**VPC network -> IP addresses ->** find your instance's ephemeral IP **->
Reserve static address ->** name it `jobpilot-ip` -> **Reserve**.

---

## Part 2 - Create an SSH key (no gcloud needed)

On your laptop, in PowerShell:

```powershell
ssh-keygen -t ed25519 -C "jobpilot" -f "$env:USERPROFILE\.ssh\jobpilot_key"
```

Press Enter twice for no passphrase (or set one and remember it).

Print the public key:

```powershell
Get-Content "$env:USERPROFILE\.ssh\jobpilot_key.pub"
```

Copy the whole line, starting with `ssh-ed25519` and ending with `jobpilot`.

Now in the console: **Compute Engine -> Metadata -> SSH Keys tab -> Add SSH key
-> Paste key -> Save**.

The **username is the last part of the key** - with `-C "jobpilot"` it is
`jobpilot`. If you used your email instead, the username is the part before `@`.

Test it:

```powershell
ssh -i "$env:USERPROFILE\.ssh\jobpilot_key" jobpilot@<EXTERNAL_IP>
```

Type `yes` at the fingerprint prompt.

---

## Part 3 - Install Docker and add swap

Inside the SSH session:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
docker --version && docker compose version
```

Now the swap file. This is what makes 1 GB survivable:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
sudo sysctl -w vm.swappiness=20
echo 'vm.swappiness=20' | sudo tee -a /etc/sysctl.conf
free -h
```

`free -h` must show about 2.0Gi of swap.

---

## Part 4 - Prepare the database copy (on your laptop)

In a second PowerShell window:

```powershell
cd "C:\Users\Rakshith\Documents\Default Project\jobpilot"
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-db.ps1
```

Writes `deploy\jobpilot-db.sql` with your jobs, workflows, credentials and digest
history.

**Critical:** `.env` holds `N8N_ENCRYPTION_KEY`. Your Gmail app password and
Postgres password are encrypted with it. Copy `.env` unchanged or n8n cannot
decrypt them.

Add the memory cap to the server's `.env` later (Part 6) - not on the laptop.

---

## Part 5 - Copy the project to the VM

```powershell
cd "C:\Users\Rakshith\Documents\Default Project"
scp -i "$env:USERPROFILE\.ssh\jobpilot_key" -r .\jobpilot jobpilot@<EXTERNAL_IP>:~/
```

Verify on the server:

```bash
ls ~/jobpilot
ls -la ~/jobpilot/.env
ls -lh ~/jobpilot/deploy/jobpilot-db.sql
```

All three must exist.

---

## Part 6 - Tune for 1 GB, then start

On the server:

```bash
cd ~/jobpilot

# Cap Node's heap so n8n uses swap politely instead of being OOM-killed.
grep -q '^NODE_OPTIONS=' .env || echo 'NODE_OPTIONS=--max-old-space-size=640' >> .env

# Bring up Postgres only.
docker compose -f deploy/docker-compose.server.yml up -d postgres
sleep 20
docker compose -f deploy/docker-compose.server.yml ps
```

Wait until Postgres reports **healthy**, then restore your data:

```bash
docker compose -f deploy/docker-compose.server.yml exec -T postgres \
  psql -U n8n -d n8n < deploy/jobpilot-db.sql 2>&1 | tail -15
```

The "does not exist, skipping" lines are normal - the dump drops objects before
recreating them.

Check the numbers:

```bash
docker compose -f deploy/docker-compose.server.yml exec -T postgres \
  psql -U n8n -d n8n -c "SELECT count(*) AS jobs, count(*) FILTER (WHERE country='us') AS us FROM jobs;"
```

Expect roughly 1341 jobs and 131 US.

Start n8n:

```bash
docker compose -f deploy/docker-compose.server.yml up -d
sleep 60
docker compose -f deploy/docker-compose.server.yml ps
docker compose -f deploy/docker-compose.server.yml logs --tail=80 n8n | grep -i "active workflow" -A 8
free -h
```

You should see both containers `Up`, the active workflow list (01, 02, 03, 06,
07), and roughly 400-600 MB of RAM in use.

---

## Part 7 - Open n8n through the tunnel

n8n listens on `127.0.0.1` only, so port 5678 is not exposed to the internet.
Nothing needs to be added to the firewall.

On your laptop, keep this window open:

```powershell
ssh -i "$env:USERPROFILE\.ssh\jobpilot_key" -L 5678:localhost:5678 jobpilot@<EXTERNAL_IP> -N
```

Then browse to <http://localhost:5678> and log in with your existing n8n account
(the user table came from your dump).

Check:

1. **Overview** lists the workflows.
2. 01, 02, 03, 06, 07 are **Active**. If any is not, open it and click **Publish**.
3. Open **07** and confirm the trigger shows **JobPilot IMAP**.

---

## Part 8 - Stop the laptop copy

```powershell
cd "C:\Users\Rakshith\Documents\Default Project\jobpilot"
docker compose down
```

Run **one** instance only. Two copies poll the same Gmail inbox and post to the
same Telegram chat, which produces duplicate digests and duplicate "apply now"
alerts.

---

## Part 9 - Prove it survives a shutdown

1. In the n8n UI, open **03 · Daily Digest** and click **Execute Workflow**.
2. Confirm the digest arrives in Telegram.
3. Shut your laptop down completely.
4. Wait for the next 09:00 IST slot.
5. The digest - and any Gmail "apply now" alert - must still arrive.

---

## Cost guardrails

Do these once, so a mistake cannot run up a bill:

1. **Billing -> Budgets and alerts -> Create budget**
   - Amount: `$1`
   - Alerts at 50%, 90%, 100%, email to yourself.
2. **Billing -> Reports**, group by SKU. Any Compute Engine line other than
   `E2 Micro Instance running in Americas`, or any disk above 30 GB, is a
   configuration mistake.
3. Confirm the machine type is `e2-micro` and the disk is **Standard** (not
   Balanced or SSD). SSD alone can cost more than the free allowance.
4. Check the trial end date: **Billing -> Overview -> Free credit** shows the
   days remaining. Upgrade to a paid billing account **before** it lapses if you
   want to keep the VM - the free `e2-micro` allowance continues after upgrading.

Network egress is the other trap: the free allowance is 1 GB/month from North
America. JobPilot's traffic is tiny (a few MB), but do not use the VM to download
large files.

---

## Troubleshooting

**`Permission denied (publickey)`**
The username is wrong. With `-C "jobpilot"` the user is `jobpilot`, not `ubuntu`.
Confirm the key is listed under **Compute Engine -> Metadata -> SSH Keys**.

**`docker: command not found` after installing**
Log out (`exit`) and reconnect, so the `docker` group applies.

**Containers restart in a loop**
`docker compose -f deploy/docker-compose.server.yml logs postgres` - usually a
wrong `POSTGRES_PASSWORD` in `.env`, or the dump was restored into the wrong DB.

**n8n killed, `dmesg` shows `Out of memory`**
Confirm swap is active (`free -h`), keep `NODE_OPTIONS=--max-old-space-size=640`,
and shorten execution retention in the compose file
(`EXECUTIONS_DATA_MAX_AGE`, currently 336 hours).

**Every workflow inactive after start**
Publish them once in the UI. Publishing is what registers the schedule and IMAP
triggers.

**Credentials fail to decrypt**
`.env` on the server differs from the laptop's `N8N_ENCRYPTION_KEY`. Copy the
original value; do not generate a new one.

**Disk full**
```bash
docker system df
docker image prune -a
```
Keep the 30 GB disk - a bigger one breaks the free tier.

---

## If you would rather not manage a VM

Same stack, different host, no signup lottery:

- **Hetzner CX22** (~EUR 4/month, Germany): copy Parts 3-9, skip the free tier rules.
- **Oracle Always Free** (Arm, up to 24 GB): see `deploy/ORACLE-CLOUD.md`.

Both use the identical `deploy/docker-compose.server.yml` and the same database
dump, so migrating between them later is just re-running these steps.
