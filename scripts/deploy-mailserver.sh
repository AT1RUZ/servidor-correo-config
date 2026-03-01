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

# ------------------------------------------------------------------------------
# VARIABLES DE CONFIGURACIÓN (Ajustables)
# ------------------------------------------------------------------------------
REMOTE_LOG_SERVER="" 
INITIALIZE_LOCAL_LDAP="true"
LDAP_ADMIN_PASS="admin"
# ------------------------------------------------------------------------------

# 2. Preparación inicial y Git
echo -e "${GREEN}[1/7] Preparando sistema e instalando herramientas base...${NC}"
apt update -y
apt install -y git debconf-utils

# 3. Pre-configuración de Slapd (Evita error de credenciales)
echo -e "${GREEN}[2/7] Pre-configurando LDAP para cujae.local...${NC}"
echo "slapd slapd/domain string cujae.local" | debconf-set-selections
echo "slapd slapd/internal_admin_password password $LDAP_ADMIN_PASS" | debconf-set-selections
echo "slapd slapd/internal_admin_password_again password $LDAP_ADMIN_PASS" | debconf-set-selections

# 4. Creación de Usuario Virtual de Correo (vmail)
if ! getent group vmail > /dev/null; then
    groupadd -g 5000 vmail
fi
if ! getent passwd vmail > /dev/null; then
    useradd -g vmail -u 5000 vmail -d /var/mail -s /usr/sbin/nologin
fi

# 5. Estructura de Buzones
echo -e "${GREEN}[3/7] Preparando estructura de buzones...${NC}"
mkdir -p /var/mail/vhosts/cujae.local 
chown -R vmail:vmail /var/mail 
chmod -R 770 /var/mail

# 6. Verificación de Repositorio (Modo Bootstrap)
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

# 7. Instalación de Paquetes
echo -e "${GREEN}[4/7] Instalando paquetes del servidor de correo...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt install -y \
    postfix \
    dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-ldap \
    slapd ldap-utils \
    opendkim opendkim-utils \
    spamassassin spamc \
    clamav-daemon clamav-milter clamav-freshclam \
    roundcube roundcube-sqlite3 apache2 libapache2-mod-php \
    swaks mailutils wget curl php-ldap php-imap imapsync sqlite3

# 8. Despliegue de Configuraciones
echo -e "${GREEN}[5/7] Desplegando archivos de configuración...${NC}"
mkdir -p /etc/postfix /etc/dovecot/conf.d /etc/opendkim/keys /etc/spamassassin /etc/clamav /etc/roundcube /etc/apache2/sites-available

# --- Postfix ---
[ -d "$REPO_DIR/postfix" ] && cp -rv "$REPO_DIR/postfix"/* /etc/postfix/

# --- Dovecot ---
if [ -d "$REPO_DIR/dovecot" ]; then
    [ -f "$REPO_DIR/dovecot/dovecot.conf" ] && cp -v "$REPO_DIR/dovecot/dovecot.conf" /etc/dovecot/dovecot.conf
    [ -f "$REPO_DIR/dovecot/dovecot-ldap.conf.ext" ] && cp -v "$REPO_DIR/dovecot/dovecot-ldap.conf.ext" /etc/dovecot/dovecot-ldap.conf.ext
    [ -d "$REPO_DIR/dovecot/conf.d" ] && cp -rv "$REPO_DIR/dovecot/conf.d"/* /etc/dovecot/conf.d/
fi

# --- OpenDKIM ---
if [ -d "$REPO_DIR/opendkim" ]; then
    [ -f "$REPO_DIR/opendkim/opendkim.conf" ] && cp -v "$REPO_DIR/opendkim/opendkim.conf" /etc/opendkim.conf
    [ -f "$REPO_DIR/opendkim/opendkim" ] && cp -v "$REPO_DIR/opendkim/opendkim" /etc/default/opendkim
    cp -rv "$REPO_DIR/opendkim"/* /etc/opendkim/
fi

# --- Roundcube ---
if [ -d "$REPO_DIR/roundcube" ]; then
    [ -f "$REPO_DIR/roundcube/config.inc.php" ] && cp -v "$REPO_DIR/roundcube/config.inc.php" /etc/roundcube/config.inc.php
fi

# --- SpamAssassin & ClamAV ---
[ -d "$REPO_DIR/spamassassin" ] && cp -rv "$REPO_DIR/spamassassin"/* /etc/spamassassin/
[ -d "$REPO_DIR/clamav" ] && cp -rv "$REPO_DIR/clamav"/* /etc/clamav/

# --- Apache ---
[ -f "$REPO_DIR/apache/mail.cujae.local.conf" ] && cp -v "$REPO_DIR/apache/mail.cujae.local.conf" /etc/apache2/sites-available/

# Mapeo de aliases de Postfix
postmap /etc/postfix/virtual_aliases || true

# 9. Ajuste de Permisos y Reparación de Servicios Específicos
echo -e "${GREEN}[6/7] Ajustando permisos y activando SpamAssassin...${NC}"
chown -R opendkim:opendkim /etc/opendkim/
chmod 640 /etc/opendkim/KeyTable /etc/opendkim/SigningTable /etc/opendkim/TrustedHosts || true

# SpamAssassin: Forzar activación en Debian/Ubuntu
if [ -f /etc/default/spamassassin ]; then
    sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/spamassassin
    sed -i 's/CRON=0/CRON=1/' /etc/default/spamassassin
fi

# Apache setup
a2enmod rewrite || true
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.3")
a2enmod php$PHP_VER || true
a2enconf roundcube || true
a2ensite mail.cujae.local.conf || true
a2dissite 000-default.conf || true

# Asegurar base de datos de Roundcube
if [ ! -f /var/lib/roundcube/sqlite.db ]; then
    sqlite3 /var/lib/roundcube/sqlite.db < /usr/share/dbconfig-common/data/roundcube/install/sqlite3 2>/dev/null || true
    chown www-data:www-data /var/lib/roundcube/sqlite.db
fi

# Firewall
if command -v ufw > /dev/null; then
    ufw allow 25/tcp || true
    ufw allow 80/tcp || true
    ufw allow 143/tcp || true
fi

# 10. Inicialización de LDAP Local
if [ "$INITIALIZE_LOCAL_LDAP" = "true" ] && [ -f "$REPO_DIR/ldap_scripts/initial_users.ldif" ]; then
    echo -e "${GREEN}[7/7] Inicializando usuarios en LDAP local (Estudiante1/2)...${NC}"
    # Re-configuración para asegurar que el sufijo es correcto
    if ! ldapsearch -x -b "dc=cujae,dc=local" > /dev/null 2>&1; then
        echo -e "${YELLOW}Re-configurando slapd para cujae.local...${NC}"
        dpkg-reconfigure -f noninteractive slapd || true
    fi
    ldapadd -x -D "cn=admin,dc=cujae,dc=local" -w "$LDAP_ADMIN_PASS" -f "$REPO_DIR/ldap_scripts/initial_users.ldif" || echo "Aviso: Usuarios ya existentes o falló la conexión"
fi

# 11. Reinicio de Servicios
echo -e "${GREEN}Reiniciando servicios y validando puertos...${NC}"
chmod +x "$REPO_DIR/scripts/restart-mailserver.sh"
"$REPO_DIR/scripts/restart-mailserver.sh"

echo -e "${BLUE}=== Despliegue Completado Exitosamente ===${NC}"
