# Guía de Ejecución y Registro de Resultados (Test Cases)

Este documento sirve como guía paso a paso para ejecutar cada Caso de Prueba (TC) y como plantilla oficial para documentar las evidencias (código de salida o capturas) obtenidas durante la validación del Servidor de Correo.

---

## Instrucciones Generales para el Probador

1. **Entorno**: Asegúrate de que tu máquina virtual (Ubuntu) esté corriendo y que en la consola base del servidor estén activos los logs si el TC lo requiere (`sudo journalctl -f`).
2. **Ejecución**: Copia y pega el comando de validación exactamente como aparece en la sección "Paso a realizar".
3. **Registro**: Debajo de cada caso de prueba, en la sección **EVIDENCIA OBTENIDA**, pega la salida textual de la consola (dentro de bloques de código ````text ... ````) o indica si adjuntarás una captura de pantalla.
4. **Cierre**: Cambia el `[ ]` por `[x]` y el `ESTADO: PENDIENTE` por `PASSED` o `FAILED` según el resultado.

---

## 🛠️ EJECUCIÓN DE PRUEBAS

### [ ] TC-01: Validación de Directorio LDAP
**Paso a realizar (Consola del servidor):**
```bash
ldapsearch -x uid=estudiante1 -b ou=people,dc=cujae,dc=local
```
**Criterio de Éxito:** Debes ver el DN del usuario, el `objectClass: inetOrgPerson` y el correo `mail: estudiante1@cujae.local`.

**ESTADO:**
**EVIDENCIA OBTENIDA:**
```text
diego@mail:~$ ldapsearch -x uid=estudiante1 -b ou=people,dc=cujae,dc=local
# extended LDIF
#
# LDAPv3
# base <ou=people,dc=cujae,dc=local> with scope subtree
# filter: uid=estudiante1
# requesting: ALL
#

# estudiante1, people, cujae.local
dn: uid=estudiante1,ou=people,dc=cujae,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: estudiante1
cn: Estudiante Uno
sn: Uno
givenName: Estudiante
mail: estudiante1@cujae.local
uidNumber: 10001
gidNumber: 10001
homeDirectory: /home/estudiante1
loginShell: /bin/bash

# search result
search: 2
result: 0 Success

# numResponses: 2
# numEntries: 1

```

---

### [ ] TC-02: Envío de Correo y Autenticación Interna (SWAKS)
**Paso a realizar (Consola del servidor):**
```bash
swaks --to estudiante1@cujae.local --from estudiante2@cujae.local --server mail.cujae.local --header "Subject: Test TC-02"
```
**Criterio de Éxito:** La transacción SMTP debe finalizar con `<~ 250 2.0.0 Ok: queued as ...`. No debe dar error de *Relay access denied*.

**ESTADO:** PENDIENTE
**EVIDENCIA OBTENIDA:**
```text
diego@mail:~$ swaks --to estudiante1@cujae.local --from estudiante2@cujae.local --server mail.cujae.local --header "Subject: Test TC-02"
=== Trying mail.cujae.local:25...
=== Connected to mail.cujae.local.
<-  220 mail.cujae.local ESMTP Postfix (Ubuntu)
 -> EHLO mail.cujae.local
<-  250-mail.cujae.local
<-  250-PIPELINING
<-  250-SIZE 10240000
<-  250-VRFY
<-  250-ETRN
<-  250-STARTTLS
<-  250-AUTH PLAIN LOGIN
<-  250-ENHANCEDSTATUSCODES
<-  250-8BITMIME
<-  250-DSN
<-  250-SMTPUTF8
<-  250 CHUNKING
 -> MAIL FROM:<estudiante2@cujae.local>
<-  250 2.1.0 Ok
 -> RCPT TO:<estudiante1@cujae.local>
<-  250 2.1.5 Ok
 -> DATA
<-  354 End data with <CR><LF>.<CR><LF>
 -> Date: Thu, 26 Feb 2026 17:14:36 -0500
 -> To: estudiante1@cujae.local
 -> From: estudiante2@cujae.local
 -> Subject: Test TC-02
 -> Message-Id: <20260226171436.007417@mail.cujae.local>
 -> X-Mailer: swaks v20240103.0 jetmore.org/john/code/swaks/
 -> 
 -> This is a test mailing
 -> 
 -> 
 -> .
<-  250 2.0.0 Ok: queued as 72D87A04E7
 -> QUIT
<-  221 2.0.0 Bye
=== Connection closed with remote host.

```

---

### [ ] TC-03: Funcionalidad de Interfaz Web (Roundcube)
**Paso a realizar (Navegador + Consola):**
1. Abre tu navegador web e ingresa a Roundcube (ej. `http://mail.cujae.local/roundcube`).
2. Loguéate como `estudiante1` y envía un correo a `estudiante2` con el asunto `Test TC-03`.
3. Para validar que Postfix entregó a Dovecot por LMTP sin error de permisos, corre en consola:
   ```bash
   sudo journalctl -u postfix -u dovecot -n 20 --no-pager
   ```

**Criterio de Éxito:** El correo llega a destino y los logs muestran `saved mail to INBOX`.

**ESTADO:** 
**EVIDENCIA OBTENIDA:**
```text
feb 26 17:18:45 mail.cujae.local dovecot[1645]: lmtp(7612): Connect from local
feb 26 17:18:45 mail.cujae.local dovecot[1645]: lmtp(estudiante2@cujae.local)<7612><igGnJ8XGoGm8HQAAM/5XIw>: msgid=<b67cc9ae451535490a826bcd77bcdde0@cujae.local>: saved mail to INBOX

Tambien puedo hacer capturas de Roundcube
```

---

### [ ] TC-04: Conectividad de Clientes Externos (Thunderbird)
**Paso a realizar (Cliente Thunderbird):**
1. Configura una cuenta nueva en Thunderbird con:
   - IMAP: Puerto `143` (STARTTLS si configuraste certificados, o Ninguno).
   - SMTP: Puerto `25` (Igual que IMAP).
2. Haz clic en el botón "Recibir mensajes".

**Criterio de Éxito:** Thunderbird sincroniza los correos sin errores de conexión. En consola (`sudo journalctl -u dovecot -n 10`) deberías ver un login exitoso `imap-login: Login: user=<estudiante1>...`.

**ESTADO:** 
**EVIDENCIA OBTENIDA:**
```text
(Pega aquí el log de dovecot demostrando la conexión IMAP remota)
```

---

### [ ] TC-05: Validación de Seguridad (DKIM)
**Paso a realizar (Consola):**
1. Envía un correo estructurado a través de SMTP local (esto obliga a pasar por los milters de Postfix):
   ```bash
   swaks --to estudiante2@cujae.local --from estudiante1@cujae.local --server mail.cujae.local --header "Subject: Prueba DKIM TC-05"
   ```
2. Revisa inmediatamente los logs:
   ```bash
   sudo journalctl -u opendkim -n 20 --no-pager
   ```

**Criterio de Éxito:** En el log debe aparecer textualmente la línea `DKIM-Signature field added (s=mail, d=cujae.local)`.

**ESTADO:** 
**EVIDENCIA OBTENIDA:**
```text
feb 26 16:27:36 mail.cujae.local systemd[1]: Starting opendkim.service - OpenDKIM Milter...
feb 26 16:27:41 mail.cujae.local systemd[1]: Started opendkim.service - OpenDKIM Milter.
feb 26 16:27:41 mail.cujae.local opendkim[1648]: OpenDKIM Filter v2.11.0 starting (args: -P /run/opendkim/opendkim.pid -p inet:8891@127.0.0.1)
feb 26 16:27:57 mail.cujae.local systemd[1]: Starting postfix.service - Postfix Mail Transport Agent...
feb 26 16:27:57 mail.cujae.local systemd[1]: Finished postfix.service - Postfix Mail Transport Agent.

```

---

### [ ] TC-06: Filtrado Antivirus y Antispam
Este caso se divide en dos pruebas diferentes. Abre dos pestañas de terminal si te es más cómodo.

#### TC-06A: SPAMASSASSIN (Prueba GTUBE)
**Paso a realizar:**
1. SpamAssassin requiere que el mensaje cuente con un formato real o que se le pida analizar el archivo puro. Validaremos usando la herramienta cliente nativa `spamc`:
   ```bash
   echo -e "Subject: GTUBE Test\n\nXJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X\n" > /tmp/gtube.eml
   spamc -R < /tmp/gtube.eml
   ```
2. Revisa la salida directa en la consola que te devolverá `spamc`.

**Criterio de Éxito:** Ver el tag formal de spam: `GTUBE` y un score total masivo `(100.../5.0)`.

**ESTADO (TC-06A):** 
**EVIDENCIA (SPAM):**
```text
feb 26 17:18:45 mail.cujae.local spamd[2228]: spamd: connection from ip6-localhost [::1]:52354 to port 783, fd 5
feb 26 17:18:45 mail.cujae.local spamd[2228]: spamd: setuid to debian-spamd succeeded
feb 26 17:18:45 mail.cujae.local spamd[2228]: spamd: processing message <b67cc9ae451535490a826bcd77bcdde0@cujae.local> for debian-spamd:130
feb 26 17:18:45 mail.cujae.local spamd[2228]: spamd: clean message (-0.2/5.0) for debian-spamd:130 in 0.4 seconds, 599 bytes.
feb 26 17:18:45 mail.cujae.local spamd[2228]: spamd: result: .  0 - ALL_TRUSTED,DKIM_ADSP_NXDOMAIN scantime=0.4,size=599,user=debian-spamd,uid=130,required_score=5.0,rhost=ip6-localhost,raddr=::1,rport=52354,mid=<b67cc9ae451535490a826bcd77bcdde0@cujae.local>,autolearn=no autolearn_force=no
feb 26 17:18:45 mail.cujae.local spamd[1530]: prefork: child states: II

```

#### TC-06B: CLAMAV (Prueba EICAR, por Consola)
**Paso a realizar:**
1. Crear el paquete de correo infectado (EICAR) y enviarlo mediante SMTP para que Postfix lo filtre con ClamAV-Milter:
   ```bash
   echo -e "Subject: Virus Test\n\nX5O!P%@AP[4\PZX54(P^)7CC)7}\$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!\$H+H*\n" > /tmp/eicar.eml
   swaks --to estudiante1@cujae.local --from estudiante2@cujae.local --server mail.cujae.local --data /tmp/eicar.eml
   ```
2. La transacción SMTP fallará inmediatamente mostrando el rechazo por pantalla. Opcionalmente, revisa el log de Postfix:
   ```bash
   sudo journalctl -u postfix -n 10 --no-pager
   ```

**Criterio de Éxito:** Roundcube lanza un error de SMTP y en la consola ves `550 5.7.1 Message rejected by milter... infected with Eicar-Signature`.

**ESTADO (TC-06B):** PENDIENTE
**EVIDENCIA (VIRUS):**
```text
(Pega aquí la transcripción del log postfix/smtpd donde se bloquea la transacción)
```

---

## 📝 Aprobación Final
Una vez que todos los cuadros estén marcados como `[x]` y los estados en `PASSED` con su correspondiente evidencia textual, este documento podrá ser marcado como finalizado.

- **Firma del Probador:** ______________
- **Fecha de Aprobación:** ____________
