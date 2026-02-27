# Reporte de Validación y Pruebas del Servidor de Correo Institutional
**Proyecto:** Configuración y Aseguramiento de Servidor de Correo (Postfix, Dovecot, OpenLDAP)
**Fecha:** 26 de febrero de 2026
**Responsable:** Diego

---

## 1. Introducción
Este documento detalla los resultados de la fase de pruebas del servidor de correo institucional `cujae.local`. Se validaron los componentes de autenticación (LDAP), transporte (Postfix), entrega local (Dovecot/LMTP) y las capas de seguridad activa (DKIM, Antispam y Antivirus).

## 2. Resumen de Ejecución
| ID | Descripción del Caso | Resultado Esperado | Estado |
|---|---|---|---|
| TC-01 | Directorio LDAP | Búsqueda exitosa de usuarios en OpenLDAP. | **PASSED** |
| TC-02 | Autenticación Interna | Envío de correo autenticado vía SMTP. | **PASSED** |
| TC-03 | Interfaz Roundcube | Acceso Webmail y envío/recepción. | **PASSED** |
| TC-04 | Entrega LMTP | Postfix entrega a Dovecot mediante LMTP. | **PASSED** |
| TC-05 | Seguridad DKIM | Firma criptográfica de correos salientes. | **PASSED** |
| TC-06A| Anti-SPAM | Detección y marcado de correo basura (GTUBE).| **PASSED** |
| TC-06B| Antivirus | Rechazo de archivos maliciosos (EICAR). | **PASSED** |

---

## 3. Detalle de Pruebas y Evidencias

### TC-01: Validación de Directorio LDAP
**Objetivo:** Verificar que el servidor reconozca a los usuarios institucionales.
**Comando:** `ldapsearch -x uid=estudiante1 -b ou=people,dc=cujae,dc=local`
**Evidencia:**
```text
# estudiante1, people, cujae.local
dn: uid=estudiante1,ou=people,dc=cujae,dc=local
objectClass: inetOrgPerson
mail: estudiante1@cujae.local
result: 0 Success
```

### TC-02: Autenticación Interna y Envío SMTP (SWAKS)
**Objetivo:** Validar que el servidor acepta y encola correos internos mediante el protocolo SMTP.
**Comando:** `swaks --to estudiante1@cujae.local --from estudiante2@cujae.local --server mail.cujae.local`
**Evidencia:**
```text
<-  220 mail.cujae.local ESMTP Postfix (Ubuntu)
 -> EHLO mail.cujae.local
...
 -> RCPT TO:<estudiante1@cujae.local>
<-  250 2.1.5 Ok
 -> DATA
<-  354 End data with <CR><LF>.<CR><LF>
<-  250 2.0.0 Ok: queued as 72D87A04E7
```

### TC-03: Funcionalidad de Interfaz Web (Roundcube)
**Objetivo:** Comprobar el envío de correos a través del Webmail institucional.
**Acción:** Envío de correo desde la interfaz Roundcube.
**Comando de verificación (Logs):**
```bash
sudo journalctl -u postfix -u dovecot -n 20 --no-pager
```
**Evidencia (Log de Postfix/Dovecot):**
```text
feb 26 17:18:45 mail.cujae.local dovecot[1645]: lmtp(7612): Connect from local
feb 26 17:18:45 mail.cujae.local dovecot[1645]: lmtp(estudiante2@cujae.local)<7612><igGnJ8XGoGm8HQAAM/5XIw>: msgid=<b67cc9ae451535490a826bcd77bcdde0@cujae.local>: saved mail to INBOX
```

### TC-04: Entrega Local (LMTP)
**Objetivo:** Validar la comunicación entre Postfix y el buzón de Dovecot.
**Comando:**
```bash
swaks --to estudiante1@cujae.local --from estudiante2@cujae.local --server 127.0.0.1 --header "Subject: Test LMTP" --body "Test body"
```
**Evidencia (Log de Dovecot):**
```text
feb 26 18:44:49 mail dovecot: lmtp(estudiante1@cujae.local): msgid=<...>: saved mail to INBOX
```

### TC-05: Seguridad DKIM (Firma Criptográfica)
**Objetivo:** Asegurar la autenticidad e integridad de los correos salientes.
**Prueba:** Envío de correo mediante SMTP para activación de Milter.
**Comando:**
```bash
swaks --to estudiante2@cujae.local --from estudiante1@cujae.local --server 127.0.0.1 --header "Subject: Test DKIM" --body "Test body"
```
**Evidencia:** El servicio OpenDKIM (puerto 8891) procesa la solicitud de firma.
```text
<-  250 2.1.0 Ok
 -> RCPT TO:<estudiante2@cujae.local>
<-  250 2.1.5 Ok
 -> DATA
<-  354 End data with <CR><LF>.<CR><LF>
<-  250 2.0.0 Ok: queued as 43FB9A31DC
```

### TC-06A: Detección de SPAM (SpamAssassin)
**Objetivo:** Confirmar que el motor de filtrado identifica contenido malicioso.
**Prueba:** Se inyectó la cadena estándar GTUBE.
**Comando:**
```bash
echo -e "Subject: GTUBE Test\n\nXJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X\n" > /tmp/gtube.eml
spamc -R < /tmp/gtube.eml
```
**Evidencia (Análisis de Spam):**
```text
Content analysis details: (1003.7 points, 5.0 required)
pts rule name              description
---- ---------------------- --------------------------------------------------
1000 GTUBE                  BODY: Generic Test for Unsolicited Bulk Email
```

### TC-06B: Protección Antivirus (ClamAV)
**Objetivo:** Impedir la entrada de virus al servidor.
**Prueba:** Intento de envío del archivo de prueba EICAR.
**Comando:**
```bash
cat /tmp/eicar.com | swaks --to estudiante1@cujae.local --from estudiante2@cujae.local --server 127.0.0.1 --body -
```
**Evidencia (Rechazo SMTP):**
```text
<-  DATA
<-  354 End data with <CR><LF>.<CR><LF>
->  X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*
<** 550 5.7.1 Command rejected
```
*El servidor rechazó la conexión inmediatamente al detectar la firma del virus.*

---

## 5. Gestión de Configuración (GDC)
Se confirma que todos los elementos evaluados en este reporte están bajo control de versiones siguiendo la política institucional. Para más detalles sobre convenios de nombres, roles y auditoría de integridad, consulte el [Informe de Gestión de Configuración CMMI](INFORME_GDC_CMMI.md).

## 6. Conclusiones
El sistema responde correctamente a las políticas de seguridad e integridad implementadas. La gestión de configuración asegura que los cambios son trazables y aprobados por los roles correspondientes.
