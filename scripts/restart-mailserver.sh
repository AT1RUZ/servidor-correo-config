#!/bin/bash
# ============================================================
#  restart-mailserver.sh
#  Reinicia todos los servicios del servidor de correo CUJAE
#  Uso: sudo ./scripts/restart-mailserver.sh
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SERVICES=(
    "opendkim"       # OpenDKIM (Port 8891)
    "postfix"        # MTA (Port 25)
    "dovecot"        # IMAP/LMTP (Port 143)
    "apache2"        # Webmail (Port 80)
)

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Reiniciando servidor de correo CUJAE     ${NC}"
echo -e "${CYAN}============================================${NC}"
echo -e "${YELLOW}Nota: ClamAV puede tardar varios minutos en iniciar.${NC}"
echo ""

for SERVICE in "${SERVICES[@]}"; do
    printf "  %-14s ... " "$SERVICE"
    
    # Intentar reiniciar con un timeout mayor para ClamAV
    if [ "$SERVICE" == "clamav-daemon" ]; then
        # Aumentar el timeout de systemd temporalmente
        systemctl restart "$SERVICE" --no-block
        # Esperar un poco a que arranque
        sleep 2
    else
        systemctl restart "$SERVICE" 2>/dev/null || true
    fi

    STATUS=$(systemctl is-active "$SERVICE")
    if [ "$STATUS" = "active" ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FALLO (o iniciando)${NC}"
    fi
done

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${YELLOW}  Verificación de Puertos:${NC}"
echo -e "${CYAN}============================================${NC}"

ALL_OK=true

check_port() {
    local PORT=$1
    local DESC=$2
    if ss -tlnp 2>/dev/null | grep -q ":$PORT "; then
        echo -e "  Puerto $PORT ($DESC)  ${GREEN}● escuchando${NC}"
        return 0
    else
        echo -e "  Puerto $PORT ($DESC)  ${RED}✗ no disponible${NC}"
        return 1
    fi
}

# Dar tiempo a que los servicios bindeen los puertos
sleep 3

check_port 25 "Postfix SMTP" || ALL_OK=false
check_port 80 "Apache HTTP" || ALL_OK=false
check_port 143 "Dovecot IMAP" || ALL_OK=false
check_port 8891 "OpenDKIM" || ALL_OK=false
check_port 8892 "ClamAV Milter" || ALL_OK=false

echo ""
if $ALL_OK; then
    echo -e "${GREEN}  ✔  Todos los servicios están activos y escuchando.${NC}"
else
    echo -e "${RED}  ✗  Error detectado o servicios aún iniciando.${NC}"
    echo -e "${YELLOW}     Si ClamAV o SpamAssassin fallaron, prueba reiniciar de nuevo en 1 minuto.${NC}"
    echo -e "${YELLOW}     tail -f /var/log/mail.log${NC}"
fi
echo -e "${CYAN}============================================${NC}"
