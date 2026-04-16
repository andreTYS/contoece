"""
OECE-IA - Servidor de IA para Contrataciones Públicas del Estado Peruano
Desarrollado con FastAPI + Claude (Anthropic) + ChromaDB (RAG)
"""

import hashlib
import logging
import os
import tempfile
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

import chromadb
from anthropic import Anthropic
from chromadb.utils.embedding_functions import SentenceTransformerEmbeddingFunction
from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, UploadFile
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
CHUNK_SIZE = 800
CHUNK_OVERLAP = 150

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
- **NO uses emojis en ninguna respuesta** — el tono es institucional y formal
- Escribe en español neutro, sin coloquialismos ni expresiones informales

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
chroma_collection: Optional[chromadb.Collection] = None
embedding_fn: Optional[SentenceTransformerEmbeddingFunction] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global anthropic_client, chroma_collection, embedding_fn
    logger.info("Iniciando servidor OECE-IA...")

    if ANTHROPIC_API_KEY:
        anthropic_client = Anthropic(api_key=ANTHROPIC_API_KEY)
        logger.info("Cliente Anthropic inicializado correctamente.")

    try:
        chroma_client = chromadb.PersistentClient(path=CHROMA_DB_PATH)
        embedding_fn = SentenceTransformerEmbeddingFunction(
            model_name="paraphrase-multilingual-MiniLM-L12-v2"
        )
        chroma_collection = chroma_client.get_or_create_collection(
            name="contrataciones_oece",
            embedding_function=embedding_fn,
            metadata={"hnsw:space": "cosine"},
        )
        logger.info(f"ChromaDB inicializado. Documentos: {chroma_collection.count()}")
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


class DocumentInfoResponse(BaseModel):
    source: str
    chunks: int
    file_hash: Optional[str] = None


# ─── Helpers de ingesta ───────────────────────────────────────────────────────

def _split_text(text: str) -> list[str]:
    if len(text) <= CHUNK_SIZE:
        return [text.strip()] if text.strip() else []
    chunks = []
    start = 0
    while start < len(text):
        end = start + CHUNK_SIZE
        if end < len(text):
            for sep in ["\n\n", "\n", ". ", " "]:
                idx = text.rfind(sep, start, end)
                if idx > start + CHUNK_SIZE // 2:
                    end = idx + len(sep)
                    break
        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        start = end - CHUNK_OVERLAP
    return chunks


def _read_file(path: Path) -> str:
    ext = path.suffix.lower()
    if ext == ".pdf":
        try:
            import pdfplumber
            parts = []
            with pdfplumber.open(str(path)) as pdf:
                for i, page in enumerate(pdf.pages):
                    t = page.extract_text()
                    if t:
                        parts.append(f"[Página {i+1}]\n{t.strip()}")
            return "\n\n".join(parts)
        except Exception as e:
            logger.error(f"Error leyendo PDF: {e}")
            return ""
    elif ext == ".docx":
        try:
            from docx import Document
            doc = Document(str(path))
            return "\n\n".join(p.text.strip() for p in doc.paragraphs if p.text.strip())
        except Exception as e:
            logger.error(f"Error leyendo DOCX: {e}")
            return ""
    elif ext in (".txt", ".md"):
        return path.read_text(encoding="utf-8", errors="ignore")
    return ""


def _file_hash(data: bytes) -> str:
    return hashlib.md5(data).hexdigest()


# ─── Endpoints principales ────────────────────────────────────────────────────

@app.get("/health", response_model=HealthResponse)
async def health_check():
    doc_count = chroma_collection.count() if chroma_collection else 0
    return HealthResponse(status="ok", documents_in_db=doc_count, model=CLAUDE_MODEL)


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    if not anthropic_client:
        raise HTTPException(
            status_code=503,
            detail="El servicio de IA no está configurado. Falta ANTHROPIC_API_KEY.",
        )

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
                if dist < 0.6
            ]
            if relevant:
                documents_found = len(relevant)
                context_text = "\n\n---\n**INFORMACIÓN DE LA BASE DE CONOCIMIENTOS OECE:**\n"
                for doc, meta in relevant:
                    source = meta.get("source", "Documento OECE")
                    page = meta.get("page", "")
                    context_text += f"\n*Fuente: {source}{f', pág. {page}' if page else ''}*\n{doc}\n"
                    label = f"{source}{f' (pág. {page})' if page else ''}"
                    if label not in sources:
                        sources.append(label)
        except Exception as e:
            logger.warning(f"Error en RAG: {e}")

    messages = [{"role": m.role, "content": m.content}
                for m in request.conversation_history[-12:]]
    user_content = request.message + (context_text if context_text else "")
    messages.append({"role": "user", "content": user_content})

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
            f"in={response.usage.input_tokens} | out={response.usage.output_tokens}"
        )
    except Exception as e:
        logger.error(f"Error al llamar a Claude: {e}")
        raise HTTPException(status_code=500, detail=f"Error al procesar: {str(e)}")

    return ChatResponse(response=answer, sources=sources, documents_found=documents_found)


@app.get("/stats")
async def get_stats():
    if not chroma_collection:
        return {"error": "Base de datos no disponible"}
    return {
        "total_documents": chroma_collection.count(),
        "collection_name": chroma_collection.name,
    }


# ─── Endpoints Admin ──────────────────────────────────────────────────────────

@app.get("/admin/documents", response_model=list[DocumentInfoResponse])
async def list_documents():
    """Lista todos los documentos en la base vectorial."""
    if not chroma_collection:
        raise HTTPException(status_code=503, detail="Base de datos no disponible")

    total = chroma_collection.count()
    if total == 0:
        return []

    all_items = chroma_collection.get(include=["metadatas"])
    sources: dict[str, dict] = {}
    for meta in all_items["metadatas"]:
        src = meta.get("source", "desconocido")
        if src not in sources:
            sources[src] = {"chunks": 0, "file_hash": meta.get("file_hash")}
        sources[src]["chunks"] += 1

    return [
        DocumentInfoResponse(source=src, chunks=info["chunks"], file_hash=info["file_hash"])
        for src, info in sorted(sources.items())
    ]


@app.post("/admin/upload")
async def upload_document(file: UploadFile = File(...)):
    """Sube e ingesta un documento (PDF, DOCX, TXT) en la base vectorial."""
    if not chroma_collection:
        raise HTTPException(status_code=503, detail="Base de datos no disponible")

    allowed_ext = {".pdf", ".docx", ".txt", ".md"}
    ext = Path(file.filename or "").suffix.lower()
    if ext not in allowed_ext:
        raise HTTPException(
            status_code=400,
            detail=f"Formato no soportado: {ext}. Usa: {', '.join(allowed_ext)}",
        )

    file_bytes = await file.read()
    fhash = _file_hash(file_bytes)
    source_name = file.filename or f"documento_{uuid.uuid4().hex[:8]}{ext}"

    # Verificar si ya existe (por hash)
    existing = chroma_collection.get(where={"file_hash": fhash})
    if existing["ids"]:
        return {
            "message": f"'{source_name}' ya existe en la base (sin cambios).",
            "chunks_added": 0,
            "source": source_name,
        }

    # Guardar temporalmente y leer
    with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as tmp:
        tmp.write(file_bytes)
        tmp_path = Path(tmp.name)

    try:
        text = _read_file(tmp_path)
    finally:
        tmp_path.unlink(missing_ok=True)

    if not text.strip():
        raise HTTPException(
            status_code=422, detail=f"'{source_name}' no tiene texto extraíble."
        )

    # Eliminar versión anterior del mismo nombre
    try:
        old = chroma_collection.get(where={"source": source_name})
        if old["ids"]:
            chroma_collection.delete(ids=old["ids"])
    except Exception:
        pass

    chunks = _split_text(text)
    ids = [str(uuid.uuid4()) for _ in chunks]
    metadatas = [
        {"source": source_name, "file_hash": fhash, "chunk_index": i, "total_chunks": len(chunks)}
        for i in range(len(chunks))
    ]
    chroma_collection.add(documents=chunks, ids=ids, metadatas=metadatas)

    logger.info(f"Admin upload: '{source_name}' → {len(chunks)} chunks")
    return {
        "message": f"'{source_name}' ingestado correctamente.",
        "chunks_added": len(chunks),
        "source": source_name,
    }


@app.delete("/admin/document/{source_name}")
async def delete_document(source_name: str):
    """Elimina un documento de la base vectorial por nombre."""
    if not chroma_collection:
        raise HTTPException(status_code=503, detail="Base de datos no disponible")

    try:
        results = chroma_collection.get(where={"source": source_name})
        if not results["ids"]:
            raise HTTPException(
                status_code=404, detail=f"Documento '{source_name}' no encontrado."
            )
        chroma_collection.delete(ids=results["ids"])
        logger.info(f"Admin delete: '{source_name}' ({len(results['ids'])} chunks)")
        return {
            "message": f"'{source_name}' eliminado correctamente.",
            "chunks_deleted": len(results["ids"]),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
