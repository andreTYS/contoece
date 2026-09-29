#!/bin/bash
# ============================================================
# OECE-IA - Script de inicio del servidor
# ============================================================

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║          OECE-IA - Servidor IA           ║"
echo "║   Asistente de Contrataciones Públicas   ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Verificar que existe el .env
if [ ! -f ".env" ]; then
    echo "⚠️  Archivo .env no encontrado."
    echo "   Copia .env.example a .env y configura tu GEMINI_API_KEY"
    echo ""
    echo "   cp .env.example .env"
    echo "   nano .env"
    exit 1
fi

# Verificar que GEMINI_API_KEY está configurada
source .env
if [ -z "$GEMINI_API_KEY" ] || [ "$GEMINI_API_KEY" = "AIzaSy-XXXXXXXXXXXXXXXXXXXXXXXXXX" ]; then
    echo "❌ GEMINI_API_KEY no configurada en .env"
    echo "   Obtén tu clave en: https://aistudio.google.com/app/apikey"
    exit 1
fi

# Verificar entorno virtual o instalar dependencias
if [ ! -d "venv" ]; then
    echo "📦 Creando entorno virtual..."
    python3 -m venv venv
fi

source venv/bin/activate
echo "📦 Verificando dependencias..."
pip install -q -r requirements.txt

# Crear directorio de datos si no existe
mkdir -p data chroma_db

# Mostrar estado de la base de datos
echo ""
echo "📚 Estado de la base de documentos:"
python3 ingest.py --list 2>/dev/null || echo "   Base vacía. Usa 'python3 ingest.py' para cargar documentos."

echo ""
PORT=${PORT:-8000}
HOST=${HOST:-0.0.0.0}
echo "🚀 Iniciando servidor en http://$HOST:$PORT"
echo "   Documentación API: http://localhost:$PORT/docs"
echo ""
echo "   Para detener el servidor presiona: Ctrl+C"
echo ""

uvicorn main:app --host "$HOST" --port "$PORT" --reload
