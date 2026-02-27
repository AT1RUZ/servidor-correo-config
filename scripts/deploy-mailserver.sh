#!/bin/bash

# ==============================================================================
# Script de Despliegue del Servidor de Correo Institucional (Basado en Guía CUJAE)
# ==============================================================================
# Este script automatiza el despliegue siguiendo las fases de la documentación
# técnica, dando prioridad a las configuraciones del repositorio.
# 
# Uso: sudo ./deploy-mailserver.sh
# ==============================================================================

set -e

# Configuración de Colores
RED="\033[0;31m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

echo -e "${BLUE}=== Iniciando Despliegue del Servidor de Correo (Flujo CUJAE) ===${NC}"

# 0. Verificación de permisos y Modo Bootstrap
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script debe ejecutarse con sudo.${NC}" 
   exit 1
fi

REPO_DIR=$(pwd)
if [ ! -d "$REPO_DIR/postfix" ] || [ ! -d "$REPO_DIR/dovecot" ]; then
    echo -e "${BLUE}No se detectaron los archivos de configuración en el directorio actual.${NC}"
    echo -n "Introduce la URL del repositorio Git de CUJAE: "
    read -r GIT_URL
    
    if [ -z "$GIT_URL" ]; then
        echo -e "${RED}Error: La URL del repositorio es obligatoria para el modo Bootstrap.${NC}"
        exit 1
    fi
    
    apt update && apt install -y git
    TEMP_DIR="/tmp/mailserver_config_$(date +%s)"
    echo -e "${GREEN}Clonando repositorio en $TEMP_DIR...${NC}"
    git clone "$GIT_URL" "$TEMP_DIR"
    cd "$TEMP_DIR" || exit 1
    REPO_DIR=$(pwd)
fi

# ------------------------------------------------------------------------------
# PARTE 1 — PREPARACIÓN DEL SISTEMA
# ------------------------------------------------------------------------------
echo -e "${GREEN}[1/8] Preparación del sistema...${NC}"
export DEBIAN_FRONTEND=noninteractive

# Intentar arreglar estados rotos de instalaciones previas
apt install -f -y || true

apt update && apt upgrade -y
apt install -y rsyslog git curl wget openssl

# Configurar Hostname
hostnamectl set-hostname mail.cujae.local
grep -q "127.0.0.1 mail.cujae.local" /etc/hosts || echo "127.0.0.1 mail.cujae.local mail" >> /etc/hosts

# Configurar Zona Horaria
timedatectl set-timezone America/Havana

# GENERACIÓN TEMPRANA DE CERTIFICADOS SSL (Evita fallos al instalar Dovecot)
echo -e "${GREEN}[1.5/8] Generando certificados SSL preventivos...${NC}"
mkdir -p /etc/ssl/private /etc/ssl/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/mailserver.key \
    -out /etc/ssl/certs/mailserver.pem \
    -subj "/C=CU/ST=La Habana/L=Marianao/O=CUJAE/OU=TIC/CN=mail.cujae.local"
chmod 600 /etc/ssl/private/mailserver.key
chown root:root /etc/ssl/private/mailserver.key

# ------------------------------------------------------------------------------
# PARTE 2 — SEGURIDAD BASE
# ------------------------------------------------------------------------------
echo -e "${GREEN}[2/8] Configurando seguridad base...${NC}"

# Usuario Administrador
if ! id "adminmail" &>/dev/null; then
    adduser --disabled-password --gecos "" adminmail
    usermod -aG sudo adminmail
    echo -e "${BLUE}Usuario 'adminmail' creado. Recuerda asignarle una contraseña manualmente.${NC}"
fi

# Firewall (UFW)
apt install ufw -y
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp  # SSH
ufw allow 25/tcp  # SMTP
ufw allow 587/tcp # SMTP Submission
ufw allow 143/tcp # IMAP
ufw allow 80/tcp  # HTTP
ufw allow 443/tcp # HTTPS
echo "y" | ufw enable

# ------------------------------------------------------------------------------
# PARTE 3 — OPENLDAP
# ------------------------------------------------------------------------------
echo -e "${GREEN}[3/8] Instalando y configurando OpenLDAP...${NC}"
apt install -y slapd ldap-utils

# Inicialización de usuarios si existe el archivo
if [ -f "$REPO_DIR/ldap_scripts/initial_users.ldif" ]; then
    echo -e "${BLUE}Cargando estructura y usuarios iniciales en LDAP...${NC}"
    # Intentar agregar, ignorar si ya existen
    ldapadd -x -D "cn=admin,dc=cujae,dc=local" -w admin -f "$REPO_DIR/ldap_scripts/initial_users.ldif" || true
fi

# ------------------------------------------------------------------------------
# PARTE 4 — POSTFIX Y DOVECOT
# ------------------------------------------------------------------------------
echo -e "${GREEN}[4/8] Instalando Postfix y Dovecot...${NC}"
apt install -y postfix postfix-ldap \
    dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-ldap

# Usuario Virtual de Correo (vmail)
if ! getent group vmail > /dev/null; then groupadd -g 5000 vmail; fi
if ! getent passwd vmail > /dev/null; then
    useradd -g vmail -u 5000 vmail -d /var/mail -s /usr/sbin/nologin
fi

# Estructura de Buzones
mkdir -p /var/mail/vhosts/cujae.local 
chown -R vmail:vmail /var/mail 
chmod -R 770 /var/mail

# Despliegue de Configuraciones del Repositorio
cp -rv "$REPO_DIR/postfix"/* /etc/postfix/
cp -rv "$REPO_DIR/dovecot"/* /etc/dovecot/

# Mapeo de aliases
postmap /etc/postfix/virtual_aliases || true

# ------------------------------------------------------------------------------
# PARTE 5 — SEGURIDAD AVANZADA (OpenDKIM, SpamAssassin, ClamAV)
# ------------------------------------------------------------------------------
echo -e "${GREEN}[6/8] Configurando seguridad avanzada...${NC}"
apt install -y opendkim opendkim-utils spamassassin spamc clamav-daemon clamav-milter

# Copiar configuraciones
[ -d "$REPO_DIR/opendkim" ] && cp -rv "$REPO_DIR/opendkim"/* /etc/opendkim/
[ -d "$REPO_DIR/spamassassin" ] && cp -rv "$REPO_DIR/spamassassin"/* /etc/spamassassin/
[ -d "$REPO_DIR/clamav" ] && cp -rv "$REPO_DIR/clamav"/* /etc/clamav/

# Permisos DKIM
chown -R opendkim:opendkim /etc/opendkim/
[ -d /etc/opendkim/keys ] && chmod 700 /etc/opendkim/keys

# ------------------------------------------------------------------------------
# PARTE 7 — ROUNDCUBE Y APACHE
# ------------------------------------------------------------------------------
echo -e "${GREEN}[7/8] Instalando Roundcube y MariaDB...${NC}"
apt install -y mariadb-server apache2 libapache2-mod-php \
    roundcube roundcube-mysql roundcube-plugins php-ldap php-imap php-gd php-xml php-mbstring php-curl php-zip php-intl

# Desplegar configuraciones
[ -d "$REPO_DIR/roundcube" ] && cp -rv "$REPO_DIR/roundcube"/* /etc/roundcube/
[ -f "$REPO_DIR/apache/mail.cujae.local.conf" ] && cp -v "$REPO_DIR/apache/mail.cujae.local.conf" /etc/apache2/sites-available/

# Apache setup
a2ensite mail.cujae.local.conf || true
a2dissite 000-default.conf || true

# ------------------------------------------------------------------------------
# PARTE 8 — FINALIZACIÓN Y VERIFICACIÓN
# ------------------------------------------------------------------------------
echo -e "${GREEN}[8/8] Finalizando despliegue...${NC}"

# Ajuste final de permisos
chown -R root:root /etc/postfix /etc/dovecot
chown root:dovecot /etc/dovecot/dovecot-ldap.conf.ext || true
chmod 640 /etc/dovecot/dovecot-ldap.conf.ext || true

# Reinicio de servicios
if [ -f "$REPO_DIR/scripts/restart-mailserver.sh" ]; then
    chmod +x "$REPO_DIR/scripts/restart-mailserver.sh"
    "$REPO_DIR/scripts/restart-mailserver.sh"
fi

# Prueba básica con SWAKS
apt install -y swaks
echo -e "${BLUE}Realizando prueba de envío interna...${NC}"
swaks --to estudiante1@cujae.local --from estudiante2@cujae.local --server localhost --header "Subject: Prueba de Despliegue" || echo -e "${RED}La prueba de SWAKS falló, revisa los logs.${NC}"

echo -e "${BLUE}=== Despliegue Completado Exitosamente ===${NC}"
