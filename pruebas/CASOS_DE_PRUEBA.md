# Casos de Prueba del Servidor de Correo (Merged)

Este documento describe los procedimientos exactos y los casos de prueba formales para verificar el correcto funcionamiento de las integraciones realizadas en el servidor de correo CUJAE. Se incluyen pruebas desde la consola, SWAKS, clientes externos y la interfaz web (Roundcube), indicando la evidencia requerida en los logs del sistema.

---

## Casos de Prueba (Test Cases - TC)

### TC-01: Validación de Directorio LDAP
**Objetivo:** Comprobar que el servidor reconoce a los usuarios institucionales.
**Precondición:** El servicio `slapd` (OpenLDAP) está activo.
**Comando/Acción:** 
```bash
ldapsearch -x uid=estudiante1 -b ou=people,dc=cujae,dc=local
```
**Resultado Esperado:** Retorno de los atributos del usuario, incluyendo `objectClass: inetOrgPerson` y `mail: estudiante1@cujae.local`.

---

### TC-02: Envío de Correo y Autenticación Interna (SWAKS)
**Objetivo:** Verificar el flujo SMTP y la validación de destinatarios contra LDAP.
**Comando/Acción:** 
```bash
swaks --to estudiante1@cujae.local --from estudiante2@cujae.local --server mail.cujae.local --header "Subject: Test"
```
**Resultado Esperado:** Código de respuesta `250 2.1.5 Ok` (destinatario válido) y `250 2.0.0 Ok: queued` (mensaje aceptado en cola).

---

### TC-03: Funcionalidad de Interfaz Web (Roundcube) y Entrega LMTP (Dovecot)
**Objetivo:** Comprobar el envío y almacenamiento de correos vía web, confirmando que Postfix puede entregar a Dovecot mediante LMTP sin errores de permisos.
**Comando/Acción:** 
1. Iniciar sesión en Roundcube con `estudiante1` y enviar un correo a `estudiante2`.
2. Verificar los logs de entrega: `sudo journalctl -u postfix -u dovecot -f`
**Resultado Esperado:** 
- En Roundcube: El correo aparece en la carpeta "Sent" de `estudiante1` y en el "INBOX" de `estudiante2`.
- En Logs: `postfix/lmtp[PID]: ... status=sent (250 2.0.0 <estudiante2@cujae.local> Saved)` y `dovecot: lmtp(...): saved mail to INBOX`.

---

### TC-04: Conectividad de Clientes Externos (Thunderbird)
**Objetivo:** Demostrar la robustez de los protocolos IMAP y SMTP para clientes de escritorio.
**Comando/Acción:** Configurar manualmente Thunderbird con IMAP en el puerto 143 y SMTP en el puerto 25 sin SSL/TLS (o con STARTTLS si está habilitado).
**Resultado Esperado:** Sincronización exitosa de la bandeja de entrada y capacidad de enviar correos.

---

### TC-05: Validación de Seguridad (DKIM)
**Objetivo:** Confirmar la firma criptográfica de los mensajes salientes y su procesamiento por OpenDKIM.
**Comando/Acción:** 
1. Enviar un correo de prueba vía Roundcube o consola: `echo "Prueba de DKIM" | s-nail -s "Prueba DKIM" estudiante2@cujae.local`
2. Revisar los registros del sistema: `sudo journalctl -u postfix -u opendkim -f`
**Resultado Esperado:** Presencia de la línea `DKIM-Signature field added (s=mail, d=cujae.local)` indicando que OpenDKIM firmó y procesó el mensaje.

---

### TC-06: Filtrado Antivirus y Antispam (SpamAssassin / ClamAV)
*Nota: Si bien el sistema puede utilizar Amavis en algunos escenarios (puerto 10024), la implementación actual usa integración directa como Milter (ClamAV en puerto 8892) y filtro de contenido (SpamAssassin-spamd).*

**Objetivo:** Verificar que el flujo de correo es analizado en busca de Spam y Virus antes de la entrega.
**Comando/Acción (Antispam):**
1. Enviar cadena GTUBE:
   ```bash
   echo "XJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X" > /tmp/spamtest.txt
   mail -s "Test de SPAM" estudiante1@cujae.local < /tmp/spamtest.txt
   ```
2. Monitorear logs: `sudo journalctl -u spamd -f`
**Resultado Esperado (Antispam):** El log muestra `identified spam (1000.0/5.0)` y cabeceras de Roundcube muestran `X-Spam-Flag: YES`. Correos limpios mostrarán `clean message (-0.2/5.0)`.

**Comando/Acción (Antivirus):**
1. Intentar enviar archivo EICAR vía Roundcube.
2. Monitorear logs: `sudo journalctl -u postfix -u clamav-milter -f`
**Resultado Esperado (Antivirus):** Postfix bloqueará la entrega y el log mostrará: `Message rejected by milter: ... infected with Eicar-Signature`.

---

## Gestión de Reportes y Evidencias

Al finalizar las pruebas de una nueva configuración, el Probador emitirá un reporte (por ejemplo, en GitHub o gestor de incidencias) que incluya:

1. **ID del Caso de Prueba** ejecutado (ej. TC-05).
2. **Estado**: `PASSED` / `FAILED`.
3. **Evidencia**: Captura de pantalla del log del servidor (journalctl/tail), resultado de la terminal o captura de la interfaz de Roundcube / Thunderbird.
4. **Aprobación**: Si todas las pruebas pasan, el Probador da el visto bueno para fusionar la rama (ej. desde una `feature/xxx` hacia `main` o `develop`).
