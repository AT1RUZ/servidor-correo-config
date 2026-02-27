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
    "slapd"        # OpenLDAP  (primero: autenticación)
    "opendkim"     # OpenDKIM  (antes de Postfix: milter)
    "postfix"      # Postfix   (MTA)
    "dovecot"      # Dovecot   (IMAP/LMTP)
)

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Reiniciando servidor de correo CUJAE     ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

for SERVICE in "${SERVICES[@]}"; do
    printf "  %-12s ... " "$SERVICE"
    if systemctl restart "$SERVICE" 2>/dev/null; then
        STATUS=$(systemctl is-active "$SERVICE")
        if [ "$STATUS" = "active" ]; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FALLO (estado: $STATUS)${NC}"
            echo -e "${YELLOW}--- Logs de $SERVICE ---${NC}"
            journalctl -u "$SERVICE" -n 20 --no-pager
            echo -e "${YELLOW}-----------------------${NC}"
        fi
    else
        echo -e "${RED}ERROR al reiniciar${NC}"
        echo -e "${YELLOW}--- Logs de $SERVICE ---${NC}"
        journalctl -u "$SERVICE" -n 20 --no-pager
        echo -e "${YELLOW}-----------------------${NC}"
    fi
done

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${YELLOW}  Estado final de los servicios:${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

ALL_OK=true
for SERVICE in "${SERVICES[@]}"; do
    STATUS=$(systemctl is-active "$SERVICE" 2>/dev/null)
    if [ "$STATUS" = "active" ]; then
        printf "  %-12s ${GREEN}●  activo${NC}\n" "$SERVICE"
    else
        printf "  %-12s ${RED}✗  $STATUS${NC}\n" "$SERVICE"
        ALL_OK=false
    fi
done

echo ""

# Verificar que OpenDKIM está escuchando en el puerto TCP
if ss -tlnp 2>/dev/null | grep -q ':8891'; then
    echo -e "  Puerto 8891 (OpenDKIM)  ${GREEN}● escuchando${NC}"
else
    echo -e "  Puerto 8891 (OpenDKIM)  ${RED}✗ no disponible${NC}"
    ALL_OK=false
fi

echo ""
if $ALL_OK; then
    echo -e "${GREEN}  ✔  Todos los servicios están activos.${NC}"
else
    echo -e "${RED}  ✗  Algún servicio no arrancó correctamente. Revisa los logs.${NC}"
    echo -e "${YELLOW}     journalctl -u <servicio> -n 50${NC}"
fi
echo -e "${CYAN}============================================${NC}"
