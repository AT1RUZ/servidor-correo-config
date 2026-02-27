#!/bin/bash

# ==============================================================================
# Script de Despliegue y Portabilidad del Servidor de Correo (CUJAE)
# ==============================================================================
# Este script automatiza la instalación de paquetes y el despliegue de 
# configuraciones para Postfix, Dovecot, LDAP, OpenDKIM, SpamAssassin, ClamAV
# Roundcube y Apache.
# 
# Uso: sudo ./deploy-mailserver.sh
# ==============================================================================

set -e

# Configuración de Colores
RED="\033[0;31m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

echo -e "${BLUE}=== Iniciando Despliegue del Servidor de Correo ===${NC}"

# 1. Verificación de permisos
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script debe ejecutarse con sudo.${NC}" 
   exit 1
fi

# 2. Actualización e Instalación de Paquetes
echo -e "${GREEN}[1/5] Actualizando repositorios e instalando paquetes...${NC}"
export DEBIAN_FRONTEND=noninteractive

apt update -y
apt install -y \
    postfix \
    dovecot-core dovecot-imapd dovecot-lmtpd dovecot-ldap \
    slapd ldap-utils \
    opendkim opendkim-utils \
    spamassassin spamc \
    clamav-daemon clamav-milter clamav-freshclam \
    roundcube roundcube-sqlite3 apache2 libapache2-mod-php \
    swaks mailutils wget curl git php-ldap php-imap

# 3. Creación de directorios faltantes
echo -e "${GREEN}[2/5] Preparando estructuras de directorios...${NC}"
mkdir -p /etc/postfix
mkdir -p /etc/dovecot/conf.d
mkdir -p /etc/opendkim/keys
mkdir -p /etc/spamassassin
mkdir -p /etc/clamav
mkdir -p /etc/roundcube
mkdir -p /etc/apache2/sites-available

# 4. Despliegue de Configuraciones
echo -e "${GREEN}[3/5] Desplegando archivos de configuración...${NC}"

# Obtener la ruta del repositorio actual
REPO_DIR=$(pwd)

# Postfix
[ -d "$REPO_DIR/postfix" ] && cp -rv "$REPO_DIR/postfix"/* /etc/postfix/

# Dovecot
[ -d "$REPO_DIR/dovecot" ] && cp -rv "$REPO_DIR/dovecot"/* /etc/dovecot/

# OpenDKIM
[ -d "$REPO_DIR/opendkim" ] && cp -rv "$REPO_DIR/opendkim"/* /etc/opendkim/
# Mover archivos de la raíz que pertenecen a OpenDKIM si existen
[ -f "$REPO_DIR/KeyTable" ] && cp "$REPO_DIR/KeyTable" /etc/opendkim/
[ -f "$REPO_DIR/SigningTable" ] && cp "$REPO_DIR/SigningTable" /etc/opendkim/
[ -f "$REPO_DIR/TrustedHosts" ] && cp "$REPO_DIR/TrustedHosts" /etc/opendkim/

# SpamAssassin
[ -d "$REPO_DIR/spamassassin" ] && cp -rv "$REPO_DIR/spamassassin"/* /etc/spamassassin/

# ClamAV
[ -d "$REPO_DIR/clamav" ] && cp -rv "$REPO_DIR/clamav"/* /etc/clamav/

# Roundcube
[ -d "$REPO_DIR/roundcube" ] && cp -rv "$REPO_DIR/roundcube"/* /etc/roundcube/

# Apache (VirtualHost) mediante enlace simbólico para desarrollo o copia para prod
if [ -f "$REPO_DIR/apache/mail.cujae.local.conf" ]; then
    ln -sf "$REPO_DIR/apache/mail.cujae.local.conf" /etc/apache2/sites-available/mail.cujae.local.conf
fi

# 5. Ajuste de Permisos y DUEÑOS (CRÍTICO)
echo -e "${GREEN}[4/5] Ajustando permisos de seguridad...${NC}"

# OpenDKIM
chown -R opendkim:opendkim /etc/opendkim/
chmod 640 /etc/opendkim/KeyTable /etc/opendkim/SigningTable /etc/opendkim/TrustedHosts || true
if [ -f /etc/opendkim/keys/default.private ]; then
    chmod 600 /etc/opendkim/keys/default.private
    chown opendkim:opendkim /etc/opendkim/keys/default.private
fi

# Postfix / Dovecot
chown -R root:root /etc/postfix /etc/dovecot

# ClamAV
chown -R clamav:clamav /etc/clamav/

# Roundcube
chown -R root:www-data /etc/roundcube
chmod 640 /etc/roundcube/config.inc.php

# Apache: Habilitar sitio y configurar /etc/hosts con ambas variantes
echo -e "${GREEN}Configurando Apache y dominios locales...${NC}"
a2ensite mail.cujae.local.conf || true
a2dissite 000-default.conf || true

for DOMAIN in "mail.cujae.local" "mail.local.cujae"; do
    if ! grep -q "$DOMAIN" /etc/hosts; then
        echo "127.0.0.1 $DOMAIN" >> /etc/hosts
        echo -e "Anexada entrada $DOMAIN a /etc/hosts"
    fi
done

# 6. Reinicio coordinado de servicios
echo -e "${GREEN}[5/5] Reiniciando servicios...${NC}"
chmod +x "$REPO_DIR/scripts/restart-mailserver.sh"
"$REPO_DIR/scripts/restart-mailserver.sh"

echo -e "${BLUE}=== Despliegue Completado Exitosamente ===${NC}"
echo -e "Accede en: http://mail.cujae.local/roundcube o http://mail.local.cujae/roundcube"
