#!/bin/bash

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

# Config
DB_FILE="$HOME/.sgm_bypasser_db.json"
LOG_DIR="/tmp/.sgm_tunnels"
API_URL="http://quaxly001.hatenna.com:25452/send"
BOT_INVITE="https://discord.com/oauth2/authorize?client_id=1502918807105175732&permissions=8&integration_type=0&scope=bot+applications.commands"

mkdir -p "$LOG_DIR"

# Auto-install tmux
if ! command -v tmux &> /dev/null; then
    echo -e "${YELLOW}Installing tmux...${NC}"
    sudo apt-get update -qq && sudo apt-get install -y -qq tmux 2>/dev/null || \
    sudo yum install -y -q tmux 2>/dev/null || \
    brew install tmux 2>/dev/null
fi

# ---------- Database ----------
init_db() { [ ! -f "$DB_FILE" ] && echo '{"profiles":{}}' > "$DB_FILE"; }
load_db() { cat "$DB_FILE"; }
save_db() { echo "$1" > "$DB_FILE"; }

# ---------- Banner ----------
banner() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════╗"
    echo -e "║    SGM Bypasser Instant Temp IPv4      ║"
    echo -e "╚════════════════════════════════════════╝${NC}"
}

# ---------- Create Tunnel Script ----------
create_tunnel_script() {
    local profile_name="$1" port="$2" method="$3" user_id="$4" webhook="$5"
    local script_path="$LOG_DIR/${profile_name}_${method}_tunnel.sh"
    
    cat > "$script_path" << 'SCRIPTSTART'
#!/bin/bash
PROFILE_NAME="$1"
PORT="$2"
METHOD="$3"
USER_ID="$4"
WEBHOOK="$5"
DB_FILE="$HOME/.sgm_bypasser_db.json"
LOG_FILE="/tmp/.sgm_tunnels/${PROFILE_NAME}_${METHOD}.log"
API_URL="http://quaxly001.hatenna.com:25452/send"

log_msg() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"; }

send_notification() {
    local url="$1"
    local host=$(echo "$url" | sed -E 's|tcp://([^:]+):[0-9]+|\1|')
    local tunnel_port=$(echo "$url" | grep -oE '[0-9]+$')
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local local_port="$PORT"
    
SCRIPTSTART

    if [ "$method" = "bot" ]; then
        cat >> "$script_path" << 'BOTNOTIFY'
    FIELDS=''
    if [ "$local_port" = "22" ]; then
        FIELDS+=",{\"name\":\"➡️ SSH Command\",\"value\":\"\`\`\`ssh -p $tunnel_port root@$host\`\`\`\"}"
    fi
    FIELDS+=",{\"name\":\"➡️ Host\",\"value\":\"$host\",\"inline\":true}"
    FIELDS+=",{\"name\":\"➡️ Tunnel Port\",\"value\":\"$tunnel_port\",\"inline\":true}"
    FIELDS+=",{\"name\":\"➡️ Local Port\",\"value\":\"$local_port\",\"inline\":true}"
    
    curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "{\"user_id\":\"$USER_ID\",\"profile_name\":\"$PROFILE_NAME\",\"tunnel_url\":\"$url\",\"port\":\"$local_port\",\"action\":\"new\",\"embed\":{\"title\":\"🌐 IPv4 Tunnel Active\",\"description\":\"Your temporary tunnel for **$PROFILE_NAME** is ready!\",\"color\":3066993,\"fields\":[${FIELDS:1}],\"footer\":{\"text\":\"SGM Bypasser | 24/7 Tunnel | $timestamp\"}}}" \
        > /dev/null 2>&1
    log_msg "✅ Sent to Discord Bot"
BOTNOTIFY
    elif [ "$method" = "webhook" ]; then
        cat >> "$script_path" << 'WEBHOOKNOTIFY'
    FIELDS=''
    if [ "$local_port" = "22" ]; then
        FIELDS+=",{\"name\":\"➡️ SSH Command\",\"value\":\"\`\`\`ssh -p $tunnel_port root@$host\`\`\`\"}"
    fi
    FIELDS+=",{\"name\":\"➡️ Host\",\"value\":\"$host\",\"inline\":true}"
    FIELDS+=",{\"name\":\"➡️ Tunnel Port\",\"value\":\"$tunnel_port\",\"inline\":true}"
    FIELDS+=",{\"name\":\"➡️ Local Port\",\"value\":\"$local_port\",\"inline\":true}"
    
    curl -s -X POST "$WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "{\"embeds\":[{\"title\":\"🌐 IPv4 Tunnel Active\",\"description\":\"Your temporary tunnel for **$PROFILE_NAME** is ready!\",\"color\":3066993,\"fields\":[${FIELDS:1}],\"footer\":{\"text\":\"SGM Bypasser | 24/7 Tunnel | $timestamp\"}}]}" \
        > /dev/null 2>&1
    log_msg "✅ Sent to Webhook"
WEBHOOKNOTIFY
    fi

    cat >> "$script_path" << 'SCRIPTEND'
}

update_db() {
    python3 -c "
import json
with open('$DB_FILE') as f:
    db = json.load(f)
db['profiles']['$PROFILE_NAME']['tunnel_url_$METHOD'] = '$1'
db['profiles']['$PROFILE_NAME']['tunnel_running_$METHOD'] = True
with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)
" 2>/dev/null
}

log_msg "Monitor started: $PROFILE_NAME | Port: $PORT | Method: $METHOD"

while true; do
    log_msg "Starting Pinggy tunnel..."
    
    ssh -p 443 -R0:localhost:$PORT tcp@a.pinggy.io \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        >> "$LOG_FILE" 2>&1 &
    
    SSH_PID=$!
    
    URL=""
    for i in $(seq 1 30); do
        sleep 2
        URL=$(grep -oE 'tcp://[a-zA-Z0-9.-]+\.pinggy(-free)?\.(link|io):[0-9]+' "$LOG_FILE" | tail -1)
        [ -n "$URL" ] && break
        
        if ! kill -0 $SSH_PID 2>/dev/null; then
            sleep 1
            URL=$(grep -oE 'tcp://[a-zA-Z0-9.-]+\.pinggy(-free)?\.(link|io):[0-9]+' "$LOG_FILE" | tail -1)
            break
        fi
    done
    
    if [ -n "$URL" ]; then
        log_msg "✅ URL: $URL"
        update_db "$URL"
        send_notification "$URL"
    fi
    
    wait $SSH_PID 2>/dev/null
    
    log_msg "❌ Disconnected. Restarting in 3s..."
    sleep 3
done
SCRIPTEND

    chmod +x "$script_path"
    echo "$script_path"
}

# ---------- Tmux Manager ----------
start_tunnel_tmux() {
    local profile_name="$1" port="$2" method="$3" user_id="$4" webhook="$5"
    local session_name="sgm_${profile_name}_${method}"
    
    tmux kill-session -t "$session_name" 2>/dev/null
    sleep 0.5
    
    local tunnel_script=$(create_tunnel_script "$profile_name" "$port" "$method" "$user_id" "$webhook")
    
    tmux new-session -d -s "$session_name" "bash '$tunnel_script' '$profile_name' '$port' '$method' '$user_id' '$webhook'"
    
    sleep 2
    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo -e "\n${GREEN}✅ Tunnel started (${method})!${NC}"
        return 0
    else
        echo -e "\n${RED}❌ Failed!${NC}"
        return 1
    fi
}

stop_tunnel_tmux() {
    local profile_name="$1" method="$2"
    local session_name="sgm_${profile_name}_${method}"
    
    if ! tmux has-session -t "$session_name" 2>/dev/null; then
        return 1
    fi
    
    tmux kill-session -t "$session_name" 2>/dev/null
    rm -f "$LOG_DIR/${profile_name}_${method}.log" "$LOG_DIR/${profile_name}_${method}_tunnel.sh"
    return 0
}

is_tunnel_running() {
    local profile_name="$1" method="$2"
    tmux has-session -t "sgm_${profile_name}_${method}" 2>/dev/null
}

# ---------- Show Method Data ----------
show_method_data() {
    local p="$1" method="$2"
    banner
    echo -e "${YELLOW}${method^} Method Data: ${CYAN}$p${NC}\n"
    
    local db=$(load_db)
    local data=$(echo "$db" | jq ".profiles.\"$p\"")
    
    if [ "$method" = "bot" ]; then
        echo -e "${BLUE}Discord ID:${NC} $(echo "$data" | jq -r '.user_id // "Not set"')"
        echo -e "${BLUE}Bot Port:${NC} $(echo "$data" | jq -r '.port_bot // "Not set"')"
    else
        echo -e "${BLUE}Webhook:${NC} $(echo "$data" | jq -r '.webhook // "Not set"')"
        echo -e "${BLUE}Webhook Port:${NC} $(echo "$data" | jq -r '.port_webhook // "Not set"')"
    fi
    
    if is_tunnel_running "$p" "$method"; then
        echo -e "\n${GREEN}✅ ${method^} Tunnel Running${NC}"
        local url=$(echo "$data" | jq -r ".tunnel_url_${method} // \"\"")
        if [ "$url" != "null" ] && [ -n "$url" ]; then
            echo -e "${BLUE}URL:${NC} ${CYAN}$url${NC}"
        fi
    else
        echo -e "\n${RED}❌ ${method^} Tunnel Stopped${NC}"
    fi
    
    echo -ne "\n${PURPLE}Press Enter...${NC}"
    read -r
}

# ---------- Status All ----------
status_all() {
    banner
    echo -e "${YELLOW}📊 Status All Profiles${NC}\n"
    
    local db=$(load_db)
    local profiles=$(echo "$db" | jq -r '.profiles | keys[]' 2>/dev/null)
    
    if [ -z "$profiles" ]; then
        echo -e "${RED}No profiles found!${NC}"
    else
        printf "${PURPLE}%-15s %-10s %-10s %-12s %-12s %-10s${NC}\n" "Profile" "Bot Port" "Web Port" "Bot" "Webhook" "Status"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        while IFS= read -r p; do
            local port_bot=$(echo "$db" | jq -r ".profiles.\"$p\".port_bot // \"-\"")
            local port_webhook=$(echo "$db" | jq -r ".profiles.\"$p\".port_webhook // \"-\"")
            local has_bot=$(echo "$db" | jq -r ".profiles.\"$p\".user_id // \"null\"")
            local has_webhook=$(echo "$db" | jq -r ".profiles.\"$p\".webhook // \"null\"")
            
            local bot_status="❌"
            local webhook_status="❌"
            local bot_configured=""
            local webhook_configured=""
            
            [ "$has_bot" != "null" ] && bot_configured="✅"
            [ "$has_webhook" != "null" ] && webhook_configured="✅"
            
            is_tunnel_running "$p" "bot" && bot_status="🟢"
            is_tunnel_running "$p" "webhook" && webhook_status="🟢"
            
            local bot_display="${bot_status}"
            [ -n "$bot_configured" ] && bot_display="${bot_status}(${bot_configured})"
            
            local webhook_display="${webhook_status}"
            [ -n "$webhook_configured" ] && webhook_display="${webhook_status}(${webhook_configured})"
            
            local overall="Idle"
            is_tunnel_running "$p" "bot" || is_tunnel_running "$p" "webhook" && overall="🟢 Active"
            
            echo -ne "${CYAN}$(printf '%-15s' "$p")${NC} "
            echo -ne "$(printf '%-10s' "$port_bot") "
            echo -ne "$(printf '%-10s' "$port_webhook") "
            echo -ne "$(printf '%-12s' "$bot_display") "
            echo -ne "$(printf '%-12s' "$webhook_display") "
            echo -e "$overall"
            
        done <<< "$profiles"
    fi
    
    echo -ne "\n${PURPLE}Press Enter to go back...${NC}"
    read -r
}

# ---------- Restart All ----------
restart_all() {
    banner
    echo -e "${YELLOW}🔄 Restart All Tunnels${NC}\n"
    
    echo -ne "${RED}This will restart ALL tunnels. Continue? (y/n): ${NC}"
    read -r confirm
    [ "$confirm" != "y" ] && { echo -e "\n${YELLOW}Cancelled${NC}"; sleep 1; return; }
    
    local db=$(load_db)
    local profiles=$(echo "$db" | jq -r '.profiles | keys[]' 2>/dev/null)
    
    if [ -z "$profiles" ]; then
        echo -e "${RED}No profiles found!${NC}"
        sleep 2
        return
    fi
    
    while IFS= read -r p; do
        local port_bot=$(echo "$db" | jq -r ".profiles.\"$p\".port_bot")
        local port_webhook=$(echo "$db" | jq -r ".profiles.\"$p\".port_webhook")
        local user_id=$(echo "$db" | jq -r ".profiles.\"$p\".user_id")
        local webhook=$(echo "$db" | jq -r ".profiles.\"$p\".webhook")
        
        is_tunnel_running "$p" "bot" && stop_tunnel_tmux "$p" "bot"
        is_tunnel_running "$p" "webhook" && stop_tunnel_tmux "$p" "webhook"
        
        sleep 1
        
        if [ "$user_id" != "null" ] && [ "$port_bot" != "null" ] && [ -n "$port_bot" ]; then
            echo -e "${GREEN}🔄 Restarting Bot tunnel for: ${CYAN}$p${NC}"
            start_tunnel_tmux "$p" "$port_bot" "bot" "$user_id" "" > /dev/null 2>&1
        fi
        
        if [ "$webhook" != "null" ] && [ "$port_webhook" != "null" ] && [ -n "$port_webhook" ]; then
            echo -e "${GREEN}🔄 Restarting Webhook tunnel for: ${CYAN}$p${NC}"
            start_tunnel_tmux "$p" "$port_webhook" "webhook" "" "$webhook" > /dev/null 2>&1
        fi
        
        if [ "$user_id" = "null" ] && [ "$webhook" = "null" ]; then
            echo -e "${YELLOW}⏭️  Skipping ${CYAN}$p${NC} - No method configured"
        fi
    done <<< "$profiles"
    
    echo -e "\n${GREEN}✅ Restart All completed!${NC}"
    sleep 2
}

# ---------- Stop All ----------
stop_all() {
    banner
    echo -e "${YELLOW}🛑 Stop All Tunnels${NC}\n"
    
    echo -ne "${RED}This will stop ALL tunnels. Continue? (y/n): ${NC}"
    read -r confirm
    [ "$confirm" != "y" ] && { echo -e "\n${YELLOW}Cancelled${NC}"; sleep 1; return; }
    
    local db=$(load_db)
    local profiles=$(echo "$db" | jq -r '.profiles | keys[]' 2>/dev/null)
    
    if [ -z "$profiles" ]; then
        echo -e "${RED}No profiles found!${NC}"
        sleep 2
        return
    fi
    
    while IFS= read -r p; do
        echo -e "${YELLOW}Stopping tunnels for: ${CYAN}$p${NC}"
        is_tunnel_running "$p" "bot" && stop_tunnel_tmux "$p" "bot" && echo -e "  ${GREEN}✅ Bot stopped${NC}"
        is_tunnel_running "$p" "webhook" && stop_tunnel_tmux "$p" "webhook" && echo -e "  ${GREEN}✅ Webhook stopped${NC}"
    done <<< "$profiles"
    
    echo -e "\n${GREEN}✅ Stop All completed!${NC}"
    sleep 2
}

# ---------- Main Menu ----------
main_menu() {
    while true; do
        banner
        echo -e "${YELLOW}Welcome to SGM Bypasser Instant Temp IPv4${NC}"
        echo -e "${BLUE}Choose your options below:${NC}\n"
        echo -e "${GREEN}[1]${NC} Create Profile"
        echo -e "${GREEN}[2]${NC} List Profiles"
        echo -e "${GREEN}[3]${NC} Delete Profile"
        echo -e "${GREEN}[4]${NC} Open Profile"
        echo -e "${GREEN}[5]${NC} Status All"
        echo -e "${GREEN}[6]${NC} Restart All"
        echo -e "${GREEN}[7]${NC} Stop All"
        echo -e "${RED}[8]${NC} Exit\n"
        echo -ne "${PURPLE}Enter your choice: ${NC}"
        read -r choice
        
        case $choice in
            1) create_profile ;;
            2) list_profiles ;;
            3) delete_profile ;;
            4) open_profile ;;
            5) status_all ;;
            6) restart_all ;;
            7) stop_all ;;
            8) cleanup_and_exit ;;
            *) echo -e "\n${RED}Invalid option!${NC}"; sleep 1 ;;
        esac
    done
}

create_profile() {
    banner
    echo -e "${YELLOW}Create New Profile${NC}\n"
    echo -ne "${BLUE}Enter profile name: ${NC}"
    read -r profile_name
    
    [ -z "$profile_name" ] && { echo -e "\n${RED}Name cannot be empty!${NC}"; sleep 2; return; }
    
    local db=$(load_db)
    if echo "$db" | jq -e ".profiles.\"$profile_name\"" > /dev/null 2>&1; then
        echo -e "\n${RED}Profile already exists!${NC}"; sleep 2; return
    fi
    
    db=$(echo "$db" | jq ".profiles.\"$profile_name\" = {\"user_id\":null,\"webhook\":null,\"port_bot\":null,\"port_webhook\":null}")
    save_db "$db"
    
    echo -e "\n${GREEN}✅ Profile created!${NC}"; sleep 1
    profile_menu "$profile_name"
}

list_profiles() {
    banner
    echo -e "${YELLOW}Available Profiles:${NC}\n"
    
    local db=$(load_db)
    local profiles=$(echo "$db" | jq -r '.profiles | keys[]' 2>/dev/null)
    
    if [ -z "$profiles" ]; then
        echo -e "${RED}No profiles found!${NC}"
    else
        local count=1
        while IFS= read -r p; do
            local bot_running="❌"
            local webhook_running="❌"
            is_tunnel_running "$p" "bot" && bot_running="✅"
            is_tunnel_running "$p" "webhook" && webhook_running="✅"
            echo -e "${GREEN}[$count]${NC} ${CYAN}$p${NC} - Bot: $bot_running | Webhook: $webhook_running"
            count=$((count + 1))
        done <<< "$profiles"
    fi
    
    echo -ne "\n${PURPLE}Press Enter to continue...${NC}"
    read -r
}

delete_profile() {
    banner
    echo -e "${YELLOW}Delete Profile${NC}\n"
    
    local db=$(load_db)
    local profiles=$(echo "$db" | jq -r '.profiles | keys[]' 2>/dev/null)
    
    [ -z "$profiles" ] && { echo -e "${RED}No profiles!${NC}"; sleep 2; return; }
    
    echo -e "${BLUE}Available profiles:${NC}"
    while IFS= read -r p; do echo -e "  ${CYAN}• $p${NC}"; done <<< "$profiles"
    
    echo -ne "\n${RED}Enter profile name to delete: ${NC}"
    read -r profile_name
    
    if ! echo "$db" | jq -e ".profiles.\"$profile_name\"" > /dev/null 2>&1; then
        echo -e "\n${RED}Not found!${NC}"; sleep 2; return
    fi
    
    is_tunnel_running "$profile_name" "bot" && stop_tunnel_tmux "$profile_name" "bot"
    is_tunnel_running "$profile_name" "webhook" && stop_tunnel_tmux "$profile_name" "webhook"
    
    echo -ne "${RED}Are you sure? (y/n): ${NC}"
    read -r confirm
    
    if [ "$confirm" = "y" ]; then
        db=$(echo "$db" | jq "del(.profiles.\"$profile_name\")")
        save_db "$db"
        echo -e "\n${GREEN}✅ Deleted!${NC}"
    fi
    sleep 2
}

open_profile() {
    banner
    echo -e "${YELLOW}Open Profile${NC}\n"
    
    local db=$(load_db)
    local profiles=$(echo "$db" | jq -r '.profiles | keys[]' 2>/dev/null)
    
    [ -z "$profiles" ] && { echo -e "${RED}No profiles!${NC}"; sleep 2; return; }
    
    echo -e "${BLUE}Available profiles:${NC}"
    while IFS= read -r p; do echo -e "  ${CYAN}• $p${NC}"; done <<< "$profiles"
    
    echo -ne "\n${PURPLE}Enter profile name: ${NC}"
    read -r profile_name
    
    if echo "$db" | jq -e ".profiles.\"$profile_name\"" > /dev/null 2>&1; then
        profile_menu "$profile_name"
    else
        echo -e "\n${RED}Not found!${NC}"; sleep 2
    fi
}

profile_menu() {
    local p="$1"
    
    while true; do
        banner
        echo -e "${YELLOW}Profile: ${CYAN}$p${NC}"
        
        local bot_status="❌"
        local webhook_status="❌"
        is_tunnel_running "$p" "bot" && bot_status="✅"
        is_tunnel_running "$p" "webhook" && webhook_status="✅"
        
        echo -e "Bot: $bot_status | Webhook: $webhook_status"
        
        echo -e "\n${BLUE}Choose your options below:${NC}\n"
        echo -e "${GREEN}[1]${NC} Get by our Discord Bot"
        echo -e "${GREEN}[2]${NC} Get by your own Webhook"
        echo -e "${RED}[3]${NC} Back\n"
        echo -ne "${PURPLE}Enter your choice: ${NC}"
        read -r choice
        
        case $choice in
            1) bot_method "$p" ;;
            2) webhook_method "$p" ;;
            3) return ;;
            *) echo -e "\n${RED}Invalid!${NC}"; sleep 1 ;;
        esac
    done
}

# ---------- Bot Method ----------
bot_method() {
    local p="$1"
    
    while true; do
        banner
        echo -e "${YELLOW}Bot Method - Profile: ${CYAN}$p${NC}"
        is_tunnel_running "$p" "bot" && echo -e "${GREEN}Bot Tunnel: ✅ Running${NC}" || echo -e "${RED}Bot Tunnel: ❌ Stopped${NC}"
        
        echo -e "\n${BLUE}Choose options below:${NC}\n"
        echo -e "${GREEN}[1]${NC} Paste your Discord ID"
        echo -e "${GREEN}[2]${NC} Change Discord ID"
        echo -e "${GREEN}[3]${NC} Choose port to forward"
        echo -e "${GREEN}[4]${NC} Change Port"
        echo -e "${GREEN}[5]${NC} Show Data"
        echo -e "${GREEN}[6]${NC} Start Tunnel"
        echo -e "${GREEN}[7]${NC} Stop Tunnel"
        echo -e "${GREEN}[8]${NC} Clear Bot Data"
        echo -e "${RED}[9]${NC} Back\n"
        echo -ne "${PURPLE}Choice: ${NC}"
        read -r choice
        
        case $choice in
            1) set_discord_id "$p" ;;
            2) set_discord_id "$p" ;;
            3) set_port "$p" "bot" ;;
            4) set_port "$p" "bot" ;;
            5) show_method_data "$p" "bot" ;;
            6)
                if is_tunnel_running "$p" "bot"; then
                    echo -e "\n${YELLOW}⚠️  Bot tunnel already running!${NC}"; sleep 2
                else
                    start_bot_tunnel "$p"
                fi
                ;;
            7) stop_tunnel_tmux "$p" "bot" ;;
            8)
                echo -ne "\n${RED}Clear bot data? (y/n): ${NC}"
                read -r confirm
                [ "$confirm" = "y" ] && { local db=$(load_db); db=$(echo "$db" | jq ".profiles.\"$p\".user_id = null | .profiles.\"$p\".port_bot = null"); save_db "$db"; echo -e "\n${GREEN}✅ Cleared!${NC}"; }
                sleep 1
                ;;
            9) return ;;
            *) echo -e "\n${RED}Invalid!${NC}"; sleep 1 ;;
        esac
    done
}

# ---------- Webhook Method ----------
webhook_method() {
    local p="$1"
    
    while true; do
        banner
        echo -e "${YELLOW}Webhook Method - Profile: ${CYAN}$p${NC}"
        is_tunnel_running "$p" "webhook" && echo -e "${GREEN}Webhook Tunnel: ✅ Running${NC}" || echo -e "${RED}Webhook Tunnel: ❌ Stopped${NC}"
        
        echo -e "\n${BLUE}Choose options below:${NC}\n"
        echo -e "${GREEN}[1]${NC} Set Webhook"
        echo -e "${GREEN}[2]${NC} Change Webhook"
        echo -e "${GREEN}[3]${NC} Choose port to forward"
        echo -e "${GREEN}[4]${NC} Change Port"
        echo -e "${GREEN}[5]${NC} Show Data"
        echo -e "${GREEN}[6]${NC} Start Tunnel"
        echo -e "${GREEN}[7]${NC} Stop Tunnel"
        echo -e "${GREEN}[8]${NC} Clear Webhook Data"
        echo -e "${RED}[9]${NC} Back\n"
        echo -ne "${PURPLE}Choice: ${NC}"
        read -r choice
        
        case $choice in
            1) set_webhook "$p" ;;
            2) set_webhook "$p" ;;
            3) set_port "$p" "webhook" ;;
            4) set_port "$p" "webhook" ;;
            5) show_method_data "$p" "webhook" ;;
            6)
                if is_tunnel_running "$p" "webhook"; then
                    echo -e "\n${YELLOW}⚠️  Webhook tunnel already running!${NC}"; sleep 2
                else
                    start_webhook_tunnel "$p"
                fi
                ;;
            7) stop_tunnel_tmux "$p" "webhook" ;;
            8)
                echo -ne "\n${RED}Clear webhook data? (y/n): ${NC}"
                read -r confirm
                [ "$confirm" = "y" ] && { local db=$(load_db); db=$(echo "$db" | jq ".profiles.\"$p\".webhook = null | .profiles.\"$p\".port_webhook = null"); save_db "$db"; echo -e "\n${GREEN}✅ Cleared!${NC}"; }
                sleep 1
                ;;
            9) return ;;
            *) echo -e "\n${RED}Invalid!${NC}"; sleep 1 ;;
        esac
    done
}

# ---------- Start Tunnels ----------
start_bot_tunnel() {
    local p="$1"
    local db=$(load_db)
    local user_id=$(echo "$db" | jq -r ".profiles.\"$p\".user_id")
    local port=$(echo "$db" | jq -r ".profiles.\"$p\".port_bot")
    
    if [ "$user_id" = "null" ] || [ "$port" = "null" ]; then
        echo -e "\n${RED}❌ Set Discord ID and Port first!${NC}"; sleep 2; return
    fi
    
    start_tunnel_tmux "$p" "$port" "bot" "$user_id" ""
}

start_webhook_tunnel() {
    local p="$1"
    local db=$(load_db)
    local webhook=$(echo "$db" | jq -r ".profiles.\"$p\".webhook")
    local port=$(echo "$db" | jq -r ".profiles.\"$p\".port_webhook")
    
    if [ "$webhook" = "null" ] || [ "$port" = "null" ]; then
        echo -e "\n${RED}❌ Set Webhook and Port first!${NC}"; sleep 2; return
    fi
    
    start_tunnel_tmux "$p" "$port" "webhook" "" "$webhook"
}

# ---------- Setters ----------
set_discord_id() {
    banner
    echo -e "${YELLOW}Set Discord ID${NC}\n"
    echo -ne "${BLUE}Paste Discord ID: ${NC}"
    read -r id
    [ -z "$id" ] && { echo -e "\n${RED}Empty!${NC}"; sleep 2; return; }
    echo -ne "\n${YELLOW}Confirm ${CYAN}$id${YELLOW}? (y/n): ${NC}"
    read -r confirm
    [ "$confirm" = "y" ] && { local db=$(load_db); db=$(echo "$db" | jq ".profiles.\"$1\".user_id = \"$id\""); save_db "$db"; echo -e "\n${GREEN}✅ Saved!${NC}"; }
    sleep 1
}

set_port() {
    local p="$1" method="$2"
    banner
    echo -e "${YELLOW}Set Port for ${method^} Method${NC}\n"
    echo -ne "${BLUE}Enter port: ${NC}"
    read -r port
    [[ ! "$port" =~ ^[0-9]+$ ]] && { echo -e "\n${RED}Invalid!${NC}"; sleep 2; return; }
    echo -ne "\n${YELLOW}Forward port ${CYAN}$port${YELLOW} for ${method}? (y/n): ${NC}"
    read -r confirm
    [ "$confirm" = "y" ] && { local db=$(load_db); db=$(echo "$db" | jq ".profiles.\"$p\".port_${method} = \"$port\""); save_db "$db"; echo -e "\n${GREEN}✅ Saved!${NC}"; }
    sleep 1
}

set_webhook() {
    banner
    echo -e "${YELLOW}Set Webhook${NC}\n"
    echo -ne "${BLUE}Enter webhook URL: ${NC}"
    read -r webhook
    [ -z "$webhook" ] && { echo -e "\n${RED}Empty!${NC}"; sleep 2; return; }
    echo -e "\n${YELLOW}Testing...${NC}"
    curl -s -X POST "$webhook" -H "Content-Type: application/json" -d '{"content":"✅ Test!"}' > /dev/null 2>&1
    echo -ne "${YELLOW}Received test? (y/n): ${NC}"
    read -r confirm
    [ "$confirm" = "y" ] && { local db=$(load_db); db=$(echo "$db" | jq ".profiles.\"$1\".webhook = \"$webhook\""); save_db "$db"; echo -e "\n${GREEN}✅ Saved!${NC}"; }
    sleep 2
}

# ---------- Cleanup ----------
cleanup_and_exit() {
    echo -e "\n${YELLOW}Stopping all tunnels...${NC}"
    tmux ls 2>/dev/null | grep '^sgm_' | cut -d: -f1 | while read -r s; do tmux kill-session -t "$s" 2>/dev/null; done
    rm -f "$LOG_DIR"/*.log "$LOG_DIR"/*_tunnel.sh
    echo -e "${GREEN}Goodbye!${NC}"
    exit 0
}

trap cleanup_and_exit SIGINT SIGTERM

# ---------- Start ----------
init_db
main_menu
