# Fulltech VPS Deployment Guide

This repository provisions three production-ready stacks on a clean Ubuntu 22.04 VPS:

1. **Nginx Proxy Manager (NPM) + n8n**
2. **Evolution API**
3. **Chatwoot**

The `deploy.sh` script automates the entire installation, networking, and stack bootstrap sequence. Follow this guide end-to-end to secure your server, deploy the services, and perform post-installation checks.

---

## 1. Prepare the VPS

### 1.1. Update the system
```bash
sudo apt update && sudo apt upgrade -y
sudo reboot
```

### 1.2. Create a dedicated administrator (optional but recommended)
```bash
sudo adduser fulltech
sudo usermod -aG sudo fulltech
```
Log out and back in as the new user before continuing.

### 1.3. Configure SSH key authentication
1. Generate an SSH key pair **on your local machine** (skip if you already have one):
   ```bash
   ssh-keygen -t ed25519 -C "your_email@example.com"
   ```
2. Copy the public key to the VPS:
   ```bash
   ssh-copy-id fulltech@<SERVER-IP>
   ```
   *If `ssh-copy-id` is unavailable, manually append your public key to `/home/fulltech/.ssh/authorized_keys`.*
3. Harden SSH (optional but recommended):
   ```bash
   sudo nano /etc/ssh/sshd_config
   ```
   Set/confirm the following:
   ```
   PasswordAuthentication no
   PubkeyAuthentication yes
   PermitRootLogin prohibit-password
   ```
   Then restart the service:
   ```bash
   sudo systemctl restart ssh
   ```

---

## 2. Configure the firewall (UFW)
Enable Ubuntu's uncomplicated firewall and allow only the required ports:
```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status verbose
```

---

## 3. Obtain the repository
Clone (or upload) the project into your home directory:
```bash
cd ~
git clone <YOUR-REPO-URL> fulltech
cd ~/fulltech
```
If you received a ZIP archive, upload it and extract it into `~/fulltech` instead.

---

## 4. Run the automated deployment
Execute the provisioning script with elevated privileges:
```bash
sudo ./deploy.sh
```
The script will:
- Validate administrative privileges.
- Install Docker Engine and the Docker Compose plugin if missing.
- Create the `~/fulltech/{npm,evolution,chatwoot}` directory hierarchy for persistent volumes.
- Copy `.env.example` → `.env` for Evolution and Chatwoot when needed and auto-generate secure credentials.
- Create the shared Docker network `proxy-net`.
- Pull and start the stacks **in order**: NPM, Evolution, Chatwoot.
- Print follow-up steps and health check commands.

> **Tip:** Environment secrets are generated only when `.env` files are created for the first time. To rotate them later, delete the `.env` file and rerun the script (services will be redeployed with new credentials).

---

## 5. Configure Nginx Proxy Manager (NPM)
1. Browse to `http://<SERVER-IP>:81` and log in with the default credentials:
   - Email: `admin@example.com`
   - Password: `changeme`
   (You will be prompted to change them immediately.)
2. Add the following proxy hosts after pointing the DNS A records for each domain to your VPS IP:

   | Domain                  | Forward Hostname / IP | Forward Port | Scheme |
   |-------------------------|-----------------------|--------------|--------|
   | `evo.fulltechvzla.com`  | `evolution`           | `3001`       | `http` |
   | `cw.fulltechvzla.com`   | `rails`               | `3000`*      | `http` |
   | `n8n.fulltechvzla.com`  | `n8n`                 | `5678`       | `http` |

   \*Chatwoot's Rails server listens on port 3000 inside the container.

3. Under the **SSL** tab for each host, request a new Let's Encrypt certificate, agree to the terms, and enable HTTP to HTTPS redirection.

### 5.1. Obtain SSL certificates manually (optional)
If you must request certificates in advance (before creating proxy hosts), use the NPM **SSL Certificates** section to issue them. After issuance, you can attach them to the proxy hosts.

---

## 6. Initialize Evolution API
1. Retrieve the auto-generated API key:
   ```bash
   sudo cat ~/fulltech/evolution/.env | grep AUTHENTICATION_API_KEY
   ```
2. Use the key to create your first instance (example request):
   ```bash
   curl -X POST \
     -H "Content-Type: application/json" \
     -H "apikey: <PASTE-AUTHENTICATION_API_KEY>" \
     -d '{
       "name": "demo-instance",
       "description": "Instance deployed via API",
       "queue": "default"
     }' \
     https://evo.fulltechvzla.com/instance/create
   ```
3. Check the health endpoint:
   ```bash
   curl https://evo.fulltechvzla.com/health
   ```

---

## 7. Configure Chatwoot & obtain bot token for n8n
1. Visit `https://cw.fulltechvzla.com` and complete the initial onboarding (create admin user).
2. Navigate to **Settings → Inboxes → Add Inbox → Chatbot** and create a new bot inbox.
3. Create a new bot agent under **Settings → Agents** and assign it to the bot inbox.
4. Within the bot inbox, click **Configure**, enable the **API channel**, and copy the **Bot Token**. This token is required by n8n workflows to interact with Chatwoot.
5. Update your n8n workflow credentials with the copied bot token and the Chatwoot host URL (`https://cw.fulltechvzla.com`).

---

## 8. Health checks & maintenance
Use these commands/endpoints to verify each stack:

| Stack           | Command / Endpoint                                                                 |
|-----------------|-------------------------------------------------------------------------------------|
| NPM + n8n       | `sudo docker compose -f npm/docker-compose.yml ps`<br>`http://<SERVER-IP>:81` UI     |
| Evolution API   | `sudo docker compose -f evolution/docker-compose.yml ps`<br>`https://evo.fulltechvzla.com/health` |
| Chatwoot        | `sudo docker compose -f chatwoot/docker-compose.yml ps`<br>`https://cw.fulltechvzla.com` UI |

### Logs
```bash
sudo docker compose -f npm/docker-compose.yml logs -f
sudo docker compose -f evolution/docker-compose.yml logs -f evolution
sudo docker compose -f chatwoot/docker-compose.yml logs -f rails
```

### Backups
- Database volumes reside in `~/fulltech/evolution/postgres_data` and `~/fulltech/chatwoot/postgres_data`.
- Redis and n8n data are stored under their respective directories in `~/fulltech`.
- Schedule regular snapshots or `docker exec` backups depending on your retention policy.

---

## 9. Troubleshooting
- **Docker not running**: `sudo systemctl status docker` then `sudo journalctl -u docker`.
- **Containers failing**: Inspect logs with `docker compose logs` and verify `.env` values.
- **Port conflicts**: Ensure no other service uses ports 80/81/443/3001.
- **DNS propagation**: Allow time for DNS records to propagate before requesting SSL certificates.

---

## 10. Next steps
- Integrate Evolution API instances with WhatsApp devices as required by your workflow.
- Build n8n workflows using the Chatwoot bot token to automate customer interactions.
- Monitor system resources with `htop`, `docker stats`, or your preferred observability stack.

Happy deploying!
