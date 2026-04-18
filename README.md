WiFi MultiAttack - Herramienta de Auditoría WiFi

WiFi MultiAttack es un script integral en Bash para auditorías de seguridad WiFi. Automatiza la captura de handshakes WPA/WPA2, la obtención de PMKID, ataques WPS, cracking de hashes con Hashcat/John y gestión inteligente de diccionarios. Diseñado para pentesters y entusiastas de la seguridad.

---

✨ Características Principales

· Ataque combinado Handshake + PMKID en una sola ejecución.
· Detección automática de WPA2, WPA3, modo transición y PMF (802.11w).
· Captura de handshake con opciones de deauth personalizables (limitado, continuo, cliente específico).
· Escaneo de redes vulnerables a PMKID (usando hcxdumptool).
· Ataque WPS con Reaver.
· Motor de cracking integrado con Hashcat y John the Ripper:
  · Diccionario simple.
  · Reglas (best64.rule, OneRuleToRuleThemAll, dive.rule).
  · Ataques de máscara, fuerza bruta incremental.
  · Modos híbridos (diccionario + máscara).
· Gestor de diccionarios persistente:
  · Almacena contraseñas encontradas en found_pass.txt.
  · Diccionario personal My_Pwnedpass.txt.
  · Carpeta Diccionarios/ para wordlists adicionales.
  · Utilidades: estadísticas, fusión, limpieza de duplicados.
· Soporte para terminales gráficas (gnome-terminal, xterm, konsole, terminator) con ventanas flotantes automáticas (regla para bspwm).
· Modo monitor y restauración automática de la interfaz de red.
· Salidas organizadas por cada objetivo (carpeta con SSID sanitizado).

---

📦 Dependencias

El script instalará automáticamente los paquetes necesarios si faltan (requiere apt). Asegúrate de tener:

· aircrack-ng
· macchanger
· hcxdumptool / hcxtools
· hashcat
· wpasupplicant
· reaver (para ataques WPS)
· john (opcional, para John the Ripper)
· tshark (para detección de PMF)

En sistemas basados en Debian/Ubuntu, ejecuta manualmente:

```bash
sudo apt update
sudo apt install aircrack-ng macchanger hcxdumptool hcxtools hashcat wpasupplicant reaver john tshark
```

---

🚀 Instalación

```bash
git clone https://github.com/Gax-n2o/Wifi_MultiAttack.git
cd Wifi_MultiAttack
chmod +x Wifi_MultiAttack.sh
```

---

⚙️ Uso

Ejecuta siempre con privilegios de root:

```bash
sudo ./Wifi_MultiAttack.sh
```

Menú Principal

```
=== MENÚ PRINCIPAL ===
  1. Ataque combinado (Handshake + PMKID)
  2. Escanear redes vulnerables (PMKID detector)
  3. Capturar Handshake (con detección WPA2/WPA3)
  4. Ataque WPS
  5. Crackear hash existente
  6. Gestionar diccionarios
  7. Salir
```

Ejemplo de flujo típico

1. Selecciona Opción 1 (Ataque combinado).
2. Espera a que se abra la ventana de airodump-ng y anota el ESSID y canal.
3. Introduce los datos solicitados.
4. El script crea una carpeta con el nombre de la red y captura handshake y/o PMKID.
5. Al finalizar, ofrece el menú de cracking con múltiples estrategias.
6. Las contraseñas encontradas se guardan automáticamente en ~/.wifi_audit_data/found_pass.txt y en tu diccionario personal.

---

📂 Estructura de Archivos Generada

```
Wifi_MultiAttack/
├── Wifi_MultiAttack.sh
├── .wifi_audit_data/           # Datos persistentes
│   ├── found_pass.txt          # Contraseñas descubiertas
│   ├── cracked_hashes.pot      # Potfile de hashcat
│   └── My_Pwnedpass.txt        # Diccionario personal
├── Diccionarios/               # Carpeta para wordlists adicionales
├── hashes/                     # Almacén central de hashes capturados
└── NombreRed/                  # Carpeta por cada objetivo
    ├── captura_handshake_*.cap
    ├── handshake_*.22000
    ├── pmkid_*.22000
    └── clave_*.txt
```

---

⚠️ Consideraciones Legales y Éticas

Esta herramienta está destinada ÚNICAMENTE para auditorías de seguridad autorizadas y fines educativos.
El uso no autorizado contra redes ajenas es ilegal. El autor no se hace responsable del mal uso de este software.
Siempre obtén permiso explícito del propietario de la red antes de realizar pruebas.

---

🧠 Consejos de Uso

· Redes con PMF activado: El script lo detecta y advierte. Los clientes modernos pueden ignorar paquetes de deauth falsos. Prueba una captura pasiva prolongada o el ataque PMKID.
· WPA3 puro: No es posible capturar handshake tradicional. El script ofrece captura de tráfico SAE para análisis posterior.
· Diccionarios: Aprovecha el gestor para combinar wordlists y filtrar por longitud. Esto acelera el cracking.
· Hashcat: Asegúrate de tener los drivers de GPU adecuados para mejor rendimiento (OpenCL/CUDA).

---

🛠️ Personalización

· Reglas de Hashcat: Coloca tus archivos .rule en /usr/share/hashcat/rules/ o en ./rules/.
· Terminal flotante: Si usas bspwm, el script aplica automáticamente reglas floating. Para otros WMs puedes modificar la función apply_bspwm_floating_rule().

---

📸 Capturas de Pantalla

(Puedes agregar imágenes aquí mostrando la interfaz, la captura de handshake, etc.)

---

👨‍💻 Autor

N2O

---

¡Contribuciones, issues y sugerencias son bienvenidas!
