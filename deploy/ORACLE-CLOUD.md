# Moving JobPilot to Oracle Cloud (Always Free)

Goal: n8n runs 24/7 on a free cloud server, so Telegram messages keep arriving
even when your laptop is off.

**Cost:** EUR 0. Oracle's "Always Free" tier includes an ARM VM (`VM.Standard.A1.Flex`)
with up to 4 cores / 24 GB RAM. No card charge if you stay on free shapes.

**Time:** about 40 minutes, most of it waiting for the VM to boot.

**Read this first:** run only **one** JobPilot at a time. Two copies read the same
Gmail inbox and send to the same Telegram chat, so you would get duplicate
messages. Step 8 stops the laptop version.

---

## Part 1 - Create the server

1. Sign up at <https://cloud.oracle.com> and pick a home region near you
   (Frankfurt or Amsterdam are a good fit for European jobs).
2. Menu -> **Compute -> Instances -> Create instance**.
3. Name: `jobpilot`
4. **Image and shape -> Edit**
   - Image: **Ubuntu 24.04** (Canonical)
   - Shape: **VM.Standard.A1.Flex**
   - OCPUs: `2`, Memory: `12 GB` (anything within the free allowance works)
   - If Oracle says "out of host capacity", try another availability domain,
     or fall back to `VM.Standard.E2.1.Micro`. Retry later - ARM capacity frees up.
5. **Networking:** keep the default VCN, and make sure
   *Assign a public IPv4 address* is enabled.
6. **SSH keys:** choose *Generate a key pair for me*, then **download the private
   key** and keep it safe. You need it for every SSH/SCP command below.
7. **Create**. Wait until the instance state is **Running**, then copy the
   **Public IP address**.

No firewall changes are needed. This setup exposes only SSH (port 22) and keeps
n8n on localhost, reached through an SSH tunnel.

---

## Part 2 - Connect to the server

On your laptop, in PowerShell (replace the key name and IP):

```powershell
ssh -i "$env:USERPROFILE\Downloads\ssh-key-2026-11-15.key" ubuntu@<SERVER_IP>
```

First time, type `yes` when asked about the fingerprint.

If Windows complains the key file is too open, run:

```powershell
icacls "$env:USERPROFILE\Downloads\ssh-key-2026-11-15.key" /inheritance:r /grant:r "$($env:USERNAME):(R)"
```

---

## Part 3 - Install Docker on the server

Still inside the SSH session:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
docker --version
docker compose version
```

Both commands must print a version. ARM64 images for Postgres and n8n exist, so
nothing extra is needed.

---

## Part 4 - Prepare the database copy (on your laptop)

In a **second** PowerShell window:

```powershell
cd "C:\Users\Rakshith\Documents\Default Project\jobpilot"
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-db.ps1
```

This writes `deploy\jobpilot-db.sql` (~5 MB) containing your 1,300+ jobs,
workflows, credentials and digest history.

**Critical:** `.env` contains `N8N_ENCRYPTION_KEY`. Your saved credentials
(Gmail app password, Postgres password) are encrypted with it. Copy `.env`
unchanged, or n8n cannot decrypt them.

---

## Part 5 - Copy the project to the server

From the laptop PowerShell:

```powershell
cd "C:\Users\Rakshith\Documents\Default Project"
scp -i "$env:USERPROFILE\Downloads\ssh-key-2026-11-15.key" -r .\jobpilot ubuntu@<SERVER_IP>:~/
```

This copies roughly 10-20 MB. It will re-copy without the key each time if you
run it again, which is fine.

Verify on the server:

```bash
ls ~/jobpilot
ls -la ~/jobpilot/.env
ls -la ~/jobpilot/deploy/jobpilot-db.sql
```

All three must exist.

---

## Part 6 - Restore the database, then start n8n

On the server:

```bash
cd ~/jobpilot

# 1. Bring up Postgres only.
docker compose -f deploy/docker-compose.server.yml up -d postgres

# 2. Wait until it reports healthy.
docker compose -f deploy/docker-compose.server.yml ps
```

Now load your data. The init script already created the schema, so use
`--clean` (the dump includes DROP statements) and ignore the harmless
"does not exist, skipping" notices:

```bash
docker compose -f deploy/docker-compose.server.yml exec -T postgres \
  psql -U n8n -d n8n < deploy/jobpilot-db.sql 2>&1 | tail -20
```

Check the row counts:

```bash
docker compose -f deploy/docker-compose.server.yml exec -T postgres \
  psql -U n8n -d n8n -c "SELECT count(*) AS jobs, count(*) FILTER (WHERE country='us') AS us FROM jobs;"
```

You should see your real totals (about 1341 jobs, 131 US).

Then start n8n:

```bash
docker compose -f deploy/docker-compose.server.yml up -d
sleep 45
docker compose -f deploy/docker-compose.server.yml ps
docker compose -f deploy/docker-compose.server.yml logs --tail=60 n8n | grep -i "active workflow" -A 8
```

Expected: both containers `Up`, and the log lists the active workflows
(01, 02, 03, 06, 07).

---

## Part 7 - Open the n8n UI through the tunnel

n8n is bound to `127.0.0.1` on the server, so it is not reachable from the
internet. Forward it over SSH.

On your laptop, in a PowerShell window you keep open:

```powershell
ssh -i "$env:USERPROFILE\Downloads\ssh-key-2026-11-15.key" -L 5678:localhost:5678 ubuntu@<SERVER_IP> -N
```

Leave it running and browse to <http://localhost:5678>. Log in with the same
n8n account as before - the user table came from your dump.

Check:

1. **Overview** shows the workflows.
2. 01, 02, 03, 06, 07 are **Active**. If one is not, open it and click **Publish**.
3. Open **07** and confirm the trigger shows the **JobPilot IMAP** credential.

If 07 shows a missing credential, run:

```bash
cd ~/jobpilot
docker compose -f deploy/docker-compose.server.yml exec -T postgres \
  psql -U n8n -d n8n -f - < /dev/stdin <<'SQL'
UPDATE workflow_entity w
SET nodes = jsonb_set(w.nodes::jsonb, '{0,credentials}',
      jsonb_build_object('imap', jsonb_build_object('id', c.id, 'name', 'JobPilot IMAP')))::json
FROM credentials_entity c
WHERE c.type = 'imap' AND w.name LIKE '07 %';
SQL
```

That should not be necessary when you restore the same database, because the
credential row comes with it.

---

## Part 8 - Stop the laptop copy

On your laptop:

```powershell
cd "C:\Users\Rakshith\Documents\Default Project\jobpilot"
docker compose down
```

Keep the folder and `.env` as a backup. From now on the server is the only
running copy.

---

## Part 9 - Prove it works

1. On the server, trigger a digest now:

   ```bash
   cd ~/jobpilot
   docker compose -f deploy/docker-compose.server.yml exec -T n8n \
     n8n execute --id <DIGEST_WORKFLOW_ID>
   ```

   Find the id with:

   ```bash
   docker compose -f deploy/docker-compose.server.yml exec -T postgres \
     psql -U n8n -d n8n -t -A -c "SELECT id, name FROM workflow_entity WHERE name LIKE '03 %';"
   ```

   If the CLI refuses to run a scheduled workflow, use the UI instead:
   open **03 · Daily Digest** and click **Execute Workflow**.

2. Check Telegram for the digest.
3. **Shut your laptop down completely.** Wait for the next 09:00 IST slot.
4. The digest and any Gmail "apply now" alerts must still arrive.

---

## Ongoing maintenance

| Task | Command (on the server) |
|---|---|
| Status | `cd ~/jobpilot && docker compose -f deploy/docker-compose.server.yml ps` |
| Logs | `docker compose -f deploy/docker-compose.server.yml logs --tail=100 n8n` |
| Restart | `docker compose -f deploy/docker-compose.server.yml restart n8n` |
| Pull updates | `docker compose -f deploy/docker-compose.server.yml pull && docker compose -f deploy/docker-compose.server.yml up -d` |
| Backup database | `docker compose -f deploy/docker-compose.server.yml exec -T postgres pg_dump -U n8n -d n8n > ~/backup-$(date +%F).sql` |
| Free disk | `df -h` (prune executions from the n8n UI if it grows) |

Run a backup weekly and copy it to your laptop:

```powershell
scp -i "$env:USERPROFILE\Downloads\ssh-key-2026-11-15.key" ubuntu@<SERVER_IP>:~/backup-*.sql .\backups\
```

---

## Troubleshooting

**`permission denied (publickey)`**
Wrong key file or wrong user. The user is `ubuntu` for Ubuntu images, `opc` for
Oracle Linux images.

**`docker: command not found` after install**
Log out and back in (`exit`, then `ssh` again) so the group change applies.

**Containers keep restarting**
`docker compose -f deploy/docker-compose.server.yml logs postgres` - usually a
wrong `POSTGRES_PASSWORD` in `.env`, or the dump was loaded into the wrong DB.

**n8n starts but every workflow is inactive**
Publish them once in the UI. Publishing is what registers the schedule and IMAP
triggers.

**Digest arrives but email alerts do not**
Open 07 and press **Execute** once, then send a fresh LinkedIn alert. The IMAP
trigger only reacts to new unread mail.

**Credentials show "could not decrypt"**
`.env` on the server has a different `N8N_ENCRYPTION_KEY` than your laptop.
Copy the original value; do not invent a new one.

---

## If Oracle signup is rejected

Oracle sometimes declines cards or signups. Two fallbacks:

- **Google Cloud** - `e2-micro` free tier (1 GB RAM). Works, but tight: set
  `N8N_RUNNERS_ENABLED=false` and lower `EXECUTIONS_DATA_MAX_AGE` to `30`.
- **Hetzner CX22** - about EUR 4/month, no signup lottery, better performance.
  Same steps from Part 3 onward.
