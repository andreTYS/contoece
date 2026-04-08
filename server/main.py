"""
OECE-IA - Servidor de IA para Contrataciones Públicas del Estado Peruano
Desarrollado con FastAPI + Claude (Anthropic) + ChromaDB (RAG)
"""

import os
import logging
from contextlib import asynccontextmanager
from typing import Optional

import chromadb
from anthropic import Anthropic
from chromadb.utils.embedding_functions import SentenceTransformerEmbeddingFunction
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

load_dotenv()

# ─── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("oece-ia")

# ─── Configuración ────────────────────────────────────────────────────────────
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
CLAUDE_MODEL = os.getenv("CLAUDE_MODEL", "claude-sonnet-4-6")
CHROMA_DB_PATH = os.getenv("CHROMA_DB_PATH", "./chroma_db")
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")

if not ANTHROPIC_API_KEY:
    logger.warning(
        "ANTHROPIC_API_KEY no configurada. El servidor iniciará pero el chat no funcionará."
    )

# ─── Personalidad y restricción de la IA ─────────────────────────────────────
SYSTEM_PROMPT = """Eres **OECE-IA**, el asistente virtual oficial especializado en contrataciones públicas del Estado peruano, desarrollado para apoyar a funcionarios, servidores públicos y proveedores del Estado.

## Tu misión
Proporcionar información precisa, confiable y actualizada sobre el sistema de contrataciones públicas del Perú, basándote en la normativa vigente y en los documentos de la base de conocimientos de la OECE.

## Tu personalidad
- Profesional, formal y confiable
- Empático y paciente con el usuario
- Preciso y directo en tus respuestas
- Citas siempre las normas relevantes (Ley N° 30225, Reglamento, Directivas OECE, etc.)

## Temas en los que puedes ayudar
- Ley de Contrataciones del Estado (Ley N° 30225 y modificatorias)
- Reglamento de la Ley de Contrataciones
- Procedimientos de selección: Licitación Pública, Concurso Público, Adjudicación Simplificada, Subasta Inversa, Contratación Directa, etc.
- Sistema Electrónico de Contrataciones del Estado (SEACE)
- Registro Nacional de Proveedores (RNP)
- Requisitos para postores y proveedores
- Elaboración de bases, TDR y expedientes técnicos
- Ejecución contractual y adicionales de obra
- Infracciones y sanciones del Tribunal de Contrataciones
- Resoluciones y pronunciamientos de la OECE
- Opiniones y consultas institucionales

## Reglas OBLIGATORIAS
1. **SOLO** responde consultas relacionadas con contrataciones públicas del Estado peruano.
2. Si te preguntan sobre temas ajenos (política, entretenimiento, finanzas personales, etc.), responde amablemente: *"Mi especialidad es el sistema de contrataciones públicas. ¿Tienes alguna consulta en ese ámbito donde pueda ayudarte?"*
3. Cuando la información esté en la base de conocimientos proporcionada, úsala prioritariamente y menciona el documento fuente.
4. Si no tienes información suficiente, indícalo claramente y sugiere consultar la página oficial de la OECE o llamar a su central.
5. Nunca inventes normativa ni artículos que no existan.
6. Usa formato Markdown para organizar tus respuestas (negritas, listas, etc.).

## Información de contacto OECE
- Web oficial: www.gob.pe/oece
- SEACE: seace.gob.pe
- Soporte técnico de esta app: WhatsApp +51 910 561 256
"""

# ─── Inicialización de servicios ──────────────────────────────────────────────
anthropic_client: Optional[Anthropic] = None
chroma_collection = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global anthropic_client, chroma_collection
    logger.info("Iniciando servidor OECE-IA...")

    # Anthropic
    if ANTHROPIC_API_KEY:
        anthropic_client = Anthropic(api_key=ANTHROPIC_API_KEY)
        logger.info("Cliente Anthropic inicializado correctamente.")

    # ChromaDB
    try:
        chroma_client = chromadb.PersistentClient(path=CHROMA_DB_PATH)
        emb_fn = SentenceTransformerEmbeddingFunction(
            model_name="paraphrase-multilingual-MiniLM-L12-v2"
        )
        chroma_collection = chroma_client.get_or_create_collection(
            name="contrataciones_oece",
            embedding_function=emb_fn,
            metadata={"hnsw:space": "cosine"},
        )
        doc_count = chroma_collection.count()
        logger.info(
            f"ChromaDB inicializado. Documentos en base: {doc_count}"
        )
    except Exception as e:
        logger.error(f"Error al inicializar ChromaDB: {e}")

    yield

    logger.info("Servidor OECE-IA detenido.")


# ─── App FastAPI ───────────────────────────────────────────────────────────────
app = FastAPI(
    title="OECE-IA API",
    description="API del Asistente IA de Contrataciones Públicas - OECE Perú",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Modelos de datos ─────────────────────────────────────────────────────────
class ConversationMessage(BaseModel):
    role: str = Field(..., pattern="^(user|assistant)$")
    content: str


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    user_id: str = Field(default="anonymous")
    conversation_history: list[ConversationMessage] = Field(default=[])


class ChatResponse(BaseModel):
    response: str
    sources: list[str] = []
    documents_found: int = 0


class HealthResponse(BaseModel):
    status: str
    documents_in_db: int
    model: str


# ─── Endpoints ────────────────────────────────────────────────────────────────
@app.get("/health", response_model=HealthResponse)
async def health_check():
    doc_count = chroma_collection.count() if chroma_collection else 0
    return HealthResponse(
        status="ok",
        documents_in_db=doc_count,
        model=CLAUDE_MODEL,
    )


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    if not anthropic_client:
        raise HTTPException(
            status_code=503,
            detail="El servicio de IA no está configurado. Falta ANTHROPIC_API_KEY.",
        )

    # ── RAG: Buscar documentos relevantes ─────────────────────────────────────
    context_text = ""
    sources: list[str] = []
    documents_found = 0

    if chroma_collection and chroma_collection.count() > 0:
        try:
            results = chroma_collection.query(
                query_texts=[request.message],
                n_results=min(5, chroma_collection.count()),
                include=["documents", "metadatas", "distances"],
            )

            docs = results.get("documents", [[]])[0]
            metas = results.get("metadatas", [[]])[0]
            distances = results.get("distances", [[]])[0]

            relevant = [
                (doc, meta)
                for doc, meta, dist in zip(docs, metas, distances)
                if dist < 0.6  # Umbral de relevancia (distancia coseno)
            ]

            if relevant:
                documents_found = len(relevant)
                context_text = "\n\n---\n**INFORMACIÓN DE LA BASE DE CONOCIMIENTOS OECE:**\n"
                for doc, meta in relevant:
                    source = meta.get("source", "Documento OECE")
                    page = meta.get("page", "")
                    context_text += f"\n*Fuente: {source}{f', pág. {page}' if page else ''}*\n{doc}\n"
                    source_label = f"{source}{f' (pág. {page})' if page else ''}"
                    if source_label not in sources:
                        sources.append(source_label)

        except Exception as e:
            logger.warning(f"Error en RAG: {e}. Continuando sin contexto.")

    # ── Construir historial para Claude ───────────────────────────────────────
    messages = []
    for msg in request.conversation_history[-12:]:  # Últimos 12 mensajes
        messages.append({"role": msg.role, "content": msg.content})

    # Añadir el mensaje actual con contexto RAG
    user_content = request.message
    if context_text:
        user_content = f"{request.message}\n{context_text}"

    messages.append({"role": "user", "content": user_content})

    # ── Llamar a Claude ────────────────────────────────────────────────────────
    try:
        response = anthropic_client.messages.create(
            model=CLAUDE_MODEL,
            max_tokens=2048,
            system=SYSTEM_PROMPT,
            messages=messages,
        )
        answer = response.content[0].text
        logger.info(
            f"Chat | user={request.user_id} | docs={documents_found} | "
            f"tokens_in={response.usage.input_tokens} | tokens_out={response.usage.output_tokens}"
        )
    except Exception as e:
        logger.error(f"Error al llamar a Claude: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Error al procesar la consulta: {str(e)}",
        )

    return ChatResponse(
        response=answer,
        sources=sources,
        documents_found=documents_found,
    )


@app.get("/stats")
async def get_stats():
    """Estadísticas de la base de conocimientos."""
    if not chroma_collection:
        return {"error": "Base de datos no disponible"}
    return {
        "total_documents": chroma_collection.count(),
        "collection_name": chroma_collection.name,
    }
