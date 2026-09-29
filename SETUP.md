# OECE-IA — Guía de Instalación y Configuración

## Estructura del Proyecto

```
CONTRATACIONES/
├── app/           # App Flutter (móvil + web)
└── server/        # Servidor Python (IA + RAG)
```

---

## PARTE 1: Configurar el Servidor Python

### Requisitos
- Python 3.10 o superior
- Cuenta en Anthropic (para Claude): https://console.anthropic.com
- ~2 GB de espacio en disco (para el modelo de embeddings)

### Pasos

**1. Entra al directorio del servidor:**
```bash
cd server
```

**2. Crea el archivo `.env`:**
```bash
cp .env.example .env
```

**3. Edita `.env` y pon tu API Key de Anthropic:**
```
ANTHROPIC_API_KEY=sk-ant-TU_CLAVE_AQUI
```

**4. Instala dependencias (primera vez):**
```bash
python3 -m venv venv
source venv/bin/activate          # Linux/Mac
# venv\Scripts\activate           # Windows
pip install -r requirements.txt
```

**5. Inicia el servidor:**
```bash
bash start.sh
```
El servidor estará en: http://localhost:8000
Documentación API: http://localhost:8000/docs

---

## PARTE 2: Cargar documentos OECE (Data Manual)

Coloca tus archivos PDF, DOCX o TXT en la carpeta `server/data/`

```bash
# Ingestar todos los archivos de la carpeta data/
python3 ingest.py

# Ingestar un archivo específico
python3 ingest.py mis_normas.pdf

# Ver qué documentos están en la base
python3 ingest.py --list

# Limpiar toda la base y empezar de nuevo
python3 ingest.py --clear

# Re-ingestar aunque ya exista
python3 ingest.py --force
```

### Formatos soportados
- `.pdf` — PDFs de normativas, resoluciones, directivas
- `.docx` — Documentos Word
- `.txt` / `.md` — Texto plano

### Documentos recomendados para cargar
- Ley N° 30225 y sus modificatorias
- Reglamento de la Ley de Contrataciones
- Directivas OECE vigentes
- Opiniones institucionales relevantes
- Bases estándar del SEACE

---

## PARTE 3: Configurar Firebase (Google Sign-In)

### 3.1 Crear proyecto Firebase

1. Ve a: https://console.firebase.google.com
2. Crea un nuevo proyecto (ej: `oece-ia-contrataciones`)
3. En **Authentication** → **Sign-in method** → Activa **Google**

### 3.2 Registrar las plataformas

#### Para Web:
1. En Firebase Console → **Agregar app** → Web (`</>`)
2. Registra con nombre `OECE-IA Web`
3. Copia la configuración `firebaseConfig`

#### Para Android:
1. En Firebase Console → **Agregar app** → Android
2. Package name: `com.oece.contrataciones`
3. Descarga `google-services.json`
4. Copia a: `app/android/app/google-services.json`
5. Obtén tu SHA-1 del keystore:
   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android
   ```
6. Agrega el SHA-1 en Firebase Console → Configuración → Huella digital

### 3.3 Configurar FlutterFire CLI

```bash
# Instalar FlutterFire CLI
dart pub global activate flutterfire_cli

# En el directorio app/
cd app
flutterfire configure --project=TU_PROJECT_ID
```

Esto genera automáticamente el archivo `lib/firebase_options.dart` con tu configuración real.

---

## PARTE 4: Compilar la App Flutter

### Requisitos
- Flutter SDK 3.16+: https://docs.flutter.dev/get-started/install
- Android Studio (para Android)
- Chrome (para web)

### Instalar dependencias Flutter
```bash
cd app
flutter pub get
```

### Ejecutar en Web (desarrollo)
```bash
flutter run -d chrome
```

### Ejecutar en Android
```bash
flutter run -d android
```

### Compilar para producción web
```bash
flutter build web --release
```
Los archivos quedan en `app/build/web/`

### Compilar APK Android
```bash
flutter build apk --release
```

---

## PARTE 5: Despliegue en Servidor/Dominio

### Servidor Python en producción

**Con Nginx + Systemd (recomendado):**

```bash
# Instalar Nginx
sudo apt install nginx

# Configurar servicio systemd para el servidor OECE-IA
sudo nano /etc/systemd/system/oece-ia.service
```

```ini
[Unit]
Description=OECE-IA FastAPI Server
After=network.target

[Service]
User=www-data
WorkingDirectory=/ruta/a/server
Environment="PATH=/ruta/a/server/venv/bin"
ExecStart=/ruta/a/server/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable oece-ia
sudo systemctl start oece-ia
```

**Configurar Nginx como proxy:**
```nginx
server {
    listen 80;
    server_name tudominio.com;

    # API Backend
    location /api/ {
        proxy_pass http://localhost:8000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # App Flutter Web
    location / {
        root /ruta/a/app/build/web;
        try_files $uri $uri/ /index.html;
    }
}
```

**Luego cambia la URL en la app:**
`app/lib/config/app_config.dart`
```dart
static const String serverUrl = 'https://tudominio.com/api';
```

---

## PARTE 6: Número de Soporte WhatsApp

El botón de WhatsApp ya está configurado para el número:
**+51 910 561 256**

Si necesitas cambiarlo: `app/lib/config/app_config.dart`
```dart
static const String whatsappNumber = '51910561256';
```

---

## Flujo completo de uso

```
Usuario → Abre la app → Login con Gmail
         ↓
         Escribe consulta → App Flutter
         ↓
         POST /chat → Servidor Python (localhost:8000)
         ↓
         RAG busca en ChromaDB (tus documentos OECE)
         ↓
         Claude genera respuesta contextualizada
         ↓
         Respuesta mostrada en el chat
```

---

## Soporte
WhatsApp: +51 910 561 256
