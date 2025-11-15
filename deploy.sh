#!/usr/bin/env bash
set -eou pipefail

# ------------------------------------------------------------
# Fulltech VPS bootstrapper
# ------------------------------------------------------------

# Colors
if command -v tput >/dev/null 2>&1; then
  GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"
  RED="$(tput setaf 1)"
  BLUE="$(tput setaf 4)"
  BOLD="$(tput bold)"
  RESET="$(tput sgr0)"
else
  GREEN=""
  YELLOW=""
  RED=""
  BLUE=""
  BOLD=""
  RESET=""
fi

info() { echo -e "${BLUE}${BOLD}[INFO]${RESET} $1"; }
success() { echo -e "${GREEN}${BOLD}[OK]${RESET} $1"; }
warn() { echo -e "${YELLOW}${BOLD}[WARN]${RESET} $1"; }
error() { echo -e "${RED}${BOLD}[ERROR]${RESET} $1"; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      error "This script must run with administrative privileges. Try: sudo bash deploy.sh"
    else
      error "This script must be executed as root."
    fi
    exit 1
  fi
}

ensure_command() {
  local cmd="$1"
  local pkg_msg="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "Required command '$cmd' not found. ${pkg_msg}"
    exit 1
  fi
}

install_docker() {
  info "Installing Docker Engine and Compose plugin..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  fi
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  success "Docker Engine and Compose plugin installed."
}

validate_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    install_docker
  else
    info "Docker binary detected."
  fi

  if ! docker info >/dev/null 2>&1; then
    info "Restarting Docker daemon..."
    systemctl restart docker
  fi

  if ! docker info >/dev/null 2>&1; then
    error "Docker daemon is not running. Please check 'systemctl status docker'."
    exit 1
  fi
  success "Docker daemon is running."

  if ! docker compose version >/dev/null 2>&1; then
    warn "Docker Compose plugin missing. Installing..."
    install_docker
  else
    success "Docker Compose plugin available."
  fi
}

repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "$script_dir"
}

create_directories() {
  local base_dir="$HOME/fulltech"
  info "Creating data directories under $base_dir..."
  mkdir -p "$base_dir/npm"/data "$base_dir/npm"/letsencrypt "$base_dir/npm"/n8n_data
  mkdir -p "$base_dir/evolution"/postgres_data "$base_dir/evolution"/redis_data
  mkdir -p "$base_dir/chatwoot"/postgres_data "$base_dir/chatwoot"/redis_data
  success "Directory structure ready."
}

create_networks() {
  info "Ensuring Docker networks exist..."
  docker network create proxy-net >/dev/null 2>&1 || true
  success "Docker network 'proxy-net' ready."
}

copy_env_file() {
  local source_file="$1"
  local target_file="$2"
  local service_name="$3"
  local created_flag_var="$4"

  if [ -f "$target_file" ]; then
    success "${service_name} environment file already exists at $(basename "$target_file"). Skipping copy."
    eval "$created_flag_var=0"
    return
  fi

  cp "$source_file" "$target_file"
  success "${service_name} environment file created from example."
  eval "$created_flag_var=1"
}

set_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  perl -0pi -e 's/^'"$key"'=.*/'"$key"'='"$value"'/m' "$file"
}

generate_random_hex() {
  local length="$1"
  openssl rand -hex "$length"
}

configure_evolution_env() {
  local env_file="$1"
  local should_configure="$2"
  if [ "${should_configure}" != "1" ]; then
    return
  fi
  info "Configuring secure credentials for Evolution API..."
  local db_password
  db_password="$(generate_random_hex 16)"
  local api_key
  api_key="$(generate_random_hex 24)"

  set_env_var "$env_file" "POSTGRES_PASSWORD" "$db_password"
  set_env_var "$env_file" "DB_PASS" "$db_password"
  set_env_var "$env_file" "DATABASE_CONNECTION_URI" "postgresql://fulltech:${db_password}@evolution-postgres:5432/evolution_db?schema=public"
  set_env_var "$env_file" "AUTHENTICATION_API_KEY" "$api_key"
  success "Evolution API credentials randomized."
}

configure_chatwoot_env() {
  local env_file="$1"
  local should_configure="$2"
  if [ "${should_configure}" != "1" ]; then
    return
  fi
  info "Configuring secure credentials for Chatwoot..."
  local db_password redis_password secret_key
  db_password="$(generate_random_hex 16)"
  redis_password="$(generate_random_hex 16)"
  secret_key="$(generate_random_hex 32)"

  set_env_var "$env_file" "POSTGRES_PASSWORD" "$db_password"
  set_env_var "$env_file" "DATABASE_URL" "postgres://chatwoot_user:${db_password}@chatwoot-postgres:5432/chatwoot"
  set_env_var "$env_file" "REDIS_PASSWORD" "$redis_password"
  set_env_var "$env_file" "SECRET_KEY_BASE" "$secret_key"
  success "Chatwoot credentials randomized."
}

compose_stack() {
  local stack_dir="$1"
  local stack_name="$2"

  info "Deploying ${stack_name} stack..."
  (cd "$stack_dir" && docker compose pull)
  (cd "$stack_dir" && docker compose up -d --build)
  success "${stack_name} stack is up."
}

print_next_steps() {
  cat <<'MSG'

====================================================
Next Steps & Health Checks
====================================================
1. Access Nginx Proxy Manager at http://<SERVER-IP>:81
   - Default credentials: admin@example.com / changeme (prompted to change on first login).
   - Configure reverse proxy hosts once DNS records point to the server.

2. Verify running containers:
   sudo docker ps

3. Check stack logs (examples):
   sudo docker compose -f npm/docker-compose.yml logs -f app
   sudo docker compose -f evolution/docker-compose.yml logs -f evolution
   sudo docker compose -f chatwoot/docker-compose.yml logs -f rails

4. Health endpoints:
   - NPM UI: http://<SERVER-IP>:81
   - Evolution API: http://<SERVER-IP>:3001/health
   - Chatwoot: https://cw.fulltechvzla.com (after proxy + SSL)

5. Remember to secure SSH (keys only) and configure UFW to allow ports 22, 80, 443.
MSG
}

main() {
  require_root
  ensure_command "apt-get" "This script is intended for Ubuntu-based systems."
  ensure_command "perl" "Install perl-base package."
  ensure_command "openssl" "Install openssl package."

  local root_dir
  root_dir="$(repo_root)"
  cd "$root_dir"

  validate_docker
  create_directories
  create_networks

  local evolution_env_created chatwoot_env_created
  copy_env_file "$root_dir/evolution/.env.example" "$root_dir/evolution/.env" "Evolution" evolution_env_created
  copy_env_file "$root_dir/chatwoot/.env.example" "$root_dir/chatwoot/.env" "Chatwoot" chatwoot_env_created

  configure_evolution_env "$root_dir/evolution/.env" "$evolution_env_created"
  configure_chatwoot_env "$root_dir/chatwoot/.env" "$chatwoot_env_created"

  compose_stack "$root_dir/npm" "Nginx Proxy Manager & n8n"
  compose_stack "$root_dir/evolution" "Evolution API"
  compose_stack "$root_dir/chatwoot" "Chatwoot"

  print_next_steps
  success "Deployment completed successfully."
}

main "$@"
