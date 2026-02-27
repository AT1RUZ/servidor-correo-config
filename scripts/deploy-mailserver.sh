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

# 2. Preparación inicial y Git
echo -e "${GREEN}[1/6] Actualizando sistema e instalando Git...${NC}"
apt update -y
apt install -y git

# 3. Verificación de Repositorio (Modo Bootstrap)
REPO_DIR=$(pwd)
if [ ! -d "$REPO_DIR/postfix" ] || [ ! -d "$REPO_DIR/dovecot" ]; then
    echo -e "${BLUE}No se detectaron los archivos de configuración en el directorio actual.${NC}"
    echo -n "Introduce la URL del repositorio Git de CUJAE: "
    read -r GIT_URL
    
    if [ -z "$GIT_URL" ]; then
        echo -e "${RED}Error: La URL del repositorio es obligatoria.${NC}"
        exit 1
    fi
    
    TEMP_DIR="/tmp/mailserver_config_$(date +%s)"
    echo -e "${GREEN}Clonando repositorio en $TEMP_DIR...${NC}"
    git clone "$GIT_URL" "$TEMP_DIR"
    cd "$TEMP_DIR"
    REPO_DIR=$(pwd)
fi

# ------------------------------------------------------------------------------
# VARIABLES DE CONFIGURACIÓN (Ajustables)
# ------------------------------------------------------------------------------
REMOTE_LOG_SERVER="" 
INITIALIZE_LOCAL_LDAP="true"
LDAP_ADMIN_PASS="admin"
# ------------------------------------------------------------------------------

# 3. Instalación de Paquetes
echo -e "${GREEN}[2/6] Instalando paquetes del servidor de correo...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt install -y \
    postfix postfix-ldap \
    dovecot-core dovecot-imapd dovecot-pop3d dovecot-ldap dovecot-lmtpd \
    slapd ldap-utils \
    opendkim opendkim-utils \
    spamassassin spamc \
    clamav-daemon clamav-milter clamav-freshclam \
    roundcube roundcube-sqlite3 apache2 libapache2-mod-php \
    swaks mailutils wget curl php-ldap php-imap imapsync

# 4. Creación de directorios y Despliegue de Configuraciones
echo -e "${GREEN}[3/6] Desplegando archivos de configuración...${NC}"
mkdir -p /etc/postfix /etc/dovecot/conf.d /etc/opendkim/keys /etc/spamassassin /etc/clamav /etc/roundcube /etc/apache2/sites-available

# Copia de archivos desde el repositorio
[ -d "$REPO_DIR/postfix" ] && cp -rv "$REPO_DIR/postfix"/* /etc/postfix/
[ -d "$REPO_DIR/dovecot" ] && cp -rv "$REPO_DIR/dovecot"/* /etc/dovecot/
[ -d "$REPO_DIR/opendkim" ] && cp -rv "$REPO_DIR/opendkim"/* /etc/opendkim/
[ -d "$REPO_DIR/spamassassin" ] && cp -rv "$REPO_DIR/spamassassin"/* /etc/spamassassin/
[ -d "$REPO_DIR/clamav" ] && cp -rv "$REPO_DIR/clamav"/* /etc/clamav/
[ -d "$REPO_DIR/roundcube" ] && cp -rv "$REPO_DIR/roundcube"/* /etc/roundcube/
[ -f "$REPO_DIR/apache/mail.cujae.local.conf" ] && cp -v "$REPO_DIR/apache/mail.cujae.local.conf" /etc/apache2/sites-available/

# Mapeo de aliases de Postfix
postmap /etc/postfix/virtual_aliases || true

# 5. Ajuste de Permisos y Dueños
echo -e "${GREEN}[4/6] Ajustando permisos de seguridad...${NC}"
chown -R opendkim:opendkim /etc/opendkim/
# OpenDKIM permissions for tables if they exist
for FILE in "KeyTable" "SigningTable" "TrustedHosts"; do
    if [ -f "/etc/opendkim/$FILE" ]; then
        chmod 640 "/etc/opendkim/$FILE"
    fi
done
if [ -f /etc/opendkim/keys/default.private ]; then
    chmod 600 /etc/opendkim/keys/default.private
    chown opendkim:opendkim /etc/opendkim/keys/default.private
fi
chown -R root:root /etc/postfix /etc/dovecot
chown -R clamav:clamav /etc/clamav/
chown -R root:www-data /etc/roundcube
chmod 640 /etc/roundcube/config.inc.php

# Apache setup
a2ensite mail.cujae.local.conf || true
a2dissite 000-default.conf || true
for DOMAIN in "mail.cujae.local" "mail.local.cujae"; do
    grep -q "$DOMAIN" /etc/hosts || echo "127.0.0.1 $DOMAIN" >> /etc/hosts
done

# Rsyslog
if [ -n "$REMOTE_LOG_SERVER" ]; then
    echo "mail.* @@$REMOTE_LOG_SERVER:514" > /etc/rsyslog.d/50-remote.conf
    systemctl restart rsyslog
fi

# 6. Inicialización de LDAP Local
if [ "$INITIALIZE_LOCAL_LDAP" = "true" ] && [ -f "$REPO_DIR/ldap_scripts/initial_users.ldif" ]; then
    echo -e "${GREEN}[5/6] Inicializando usuarios en LDAP local...${NC}"
    ldapadd -x -D "cn=admin,dc=cujae,dc=local" -w "$LDAP_ADMIN_PASS" -f "$REPO_DIR/ldap_scripts/initial_users.ldif" || echo "Aviso: Usuarios ya existentes"
fi

# 7. Reinicio de Servicios
echo -e "${GREEN}[6/6] Reiniciando servicios...${NC}"
chmod +x "$REPO_DIR/scripts/restart-mailserver.sh"
"$REPO_DIR/scripts/restart-mailserver.sh"

echo -e "${BLUE}=== Despliegue Completado Exitosamente ===${NC}"
