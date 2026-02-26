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

**ESTADO:** PENDIENTE
**EVIDENCIA OBTENIDA:**
```text
(Pega aquí la salida completa del comando ldapsearch)
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
(Pega aquí las últimas líneas de la salida de swaks mostrando el 250 Ok)
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

**ESTADO:** PENDIENTE
**EVIDENCIA OBTENIDA:**
```text
(Pega aquí de 3 a 5 líneas del log journalctl donde se vea la transacción lmtp y "saved mail to INBOX")
/* Nota: Si también tomas captura de Roundcube, indícalo aquí */
```

---

### [ ] TC-04: Conectividad de Clientes Externos (Thunderbird)
**Paso a realizar (Cliente Thunderbird):**
1. Configura una cuenta nueva en Thunderbird con:
   - IMAP: Puerto `143` (STARTTLS si configuraste certificados, o Ninguno).
   - SMTP: Puerto `25` (Igual que IMAP).
2. Haz clic en el botón "Recibir mensajes".

**Criterio de Éxito:** Thunderbird sincroniza los correos sin errores de conexión. En consola (`sudo journalctl -u dovecot -n 10`) deberías ver un login exitoso `imap-login: Login: user=<estudiante1>...`.

**ESTADO:** PENDIENTE
**EVIDENCIA OBTENIDA:**
```text
(Pega aquí el log de dovecot demostrando la conexión IMAP remota)
```

---

### [ ] TC-05: Validación de Seguridad (DKIM)
**Paso a realizar (Consola):**
1. Envía un correo con texto:
   ```bash
   echo "Prueba TC-05" | s-nail -s "Prueba DKIM TC-05" estudiante2@cujae.local
   ```
2. Revisa inmediatamente los logs:
   ```bash
   sudo journalctl -u opendkim -u postfix -n 20 --no-pager
   ```

**Criterio de Éxito:** En el log debe aparecer textualmente la línea `DKIM-Signature field added (s=mail, d=cujae.local)`.

**ESTADO:** PENDIENTE
**EVIDENCIA OBTENIDA:**
```text
(Pega aquí las líneas del log que evidencian la firma criptográfica por opendkim)
```

---

### [ ] TC-06: Filtrado Antivirus y Antispam
Este caso se divide en dos pruebas diferentes. Abre dos pestañas de terminal si te es más cómodo.

#### TC-06A: SPAMASSASSIN (Prueba GTUBE)
**Paso a realizar:**
1. Crea el falso SPAM y envíalo:
   ```bash
   echo "XJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X" > /tmp/spamtest.txt
   mail -s "Test de SPAM TC-06A" estudiante1@cujae.local < /tmp/spamtest.txt
   ```
2. Revisa el log de SpamAssassin:
   ```bash
   sudo journalctl -u spamd -n 20 --no-pager
   ```

**Criterio de Éxito:** Ver el tag formal de spam: `result: Y 1000 - GTUBE`.

**ESTADO (TC-06A):** PENDIENTE
**EVIDENCIA (SPAM):**
```text
(Pega aquí las líneas del log de spamd identificando la amenaza)
```

#### TC-06B: CLAMAV (Prueba EICAR)
**Paso a realizar:**
1. Crear el falso Virus:
   ```bash
   echo 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > /tmp/eicar.com
   ```
2. Ingresa a Roundcube, redacta un correo nuevo, sube como adjunto el archivo `/tmp/eicar.com` y oprime *Enviar*.
3. En la consola, revisa el log de Postfix:
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
