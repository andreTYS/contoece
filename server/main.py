"""
OECE-IA - Servidor de IA para Contrataciones Públicas del Estado Peruano
Desarrollado con FastAPI + Gemini API (google-genai) + ChromaDB (RAG)
"""

import asyncio
import hashlib
import logging
import os
import re
import tempfile
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

import chromadb
import json
from chromadb import Documents, EmbeddingFunction, Embeddings
from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from google import genai
from google.genai import types
from pydantic import BaseModel, Field

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("oece-ia")

GEMINI_API_KEY        = os.getenv("GEMINI_API_KEY", "")
GEMINI_MODEL          = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
GEMINI_EMBEDDING_MODEL = os.getenv("GEMINI_EMBEDDING_MODEL", "models/text-embedding-004")
CHROMA_DB_PATH        = os.getenv("CHROMA_DB_PATH", "./chroma_db")
ALLOWED_ORIGINS       = os.getenv("ALLOWED_ORIGINS", "*").split(",")
CHUNK_SIZE   = 800
CHUNK_OVERLAP = 150

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
2. Si te preguntan sobre temas ajenos, responde: *"Mi especialidad es el sistema de contrataciones públicas. ¿Tienes alguna consulta en ese ámbito donde pueda ayudarte?"*
3. Cuando la información esté en la base de conocimientos proporcionada, úsala prioritariamente y menciona el documento fuente.
4. Si no tienes información suficiente, indícalo claramente y sugiere consultar la página oficial de la OECE.
5. Nunca inventes normativa ni artículos que no existan.
6. Usa formato Markdown para organizar tus respuestas (negritas, listas, etc.).

## Información de contacto OECE
- Web oficial: www.gob.pe/oece
- SEACE: seace.gob.pe
- Soporte técnico de esta app: WhatsApp +51 910 561 256
"""

# ─── Cliente Gemini global ────────────────────────────────────────────────────
gemini_client: Optional[genai.Client] = None


# ─── Embedding con Gemini ─────────────────────────────────────────────────────

class GeminiEmbeddingFunction(EmbeddingFunction):
    """Embedding sincrónico usando Gemini text-embedding-004 (requerido por ChromaDB)."""

    _BATCH_SIZE = 100

    def __call__(self, input: Documents) -> Embeddings:
        if not input or not gemini_client:
            return []
        all_embeddings: Embeddings = []
        for i in range(0, len(input), self._BATCH_SIZE):
            batch = list(input[i : i + self._BATCH_SIZE])
            result = gemini_client.models.embed_content(
                model=GEMINI_EMBEDDING_MODEL,
                contents=batch,
                config=types.EmbedContentConfig(task_type="RETRIEVAL_DOCUMENT"),
            )
            all_embeddings.extend([e.values for e in result.embeddings])
        return all_embeddings


# ─── Estado global ────────────────────────────────────────────────────────────
chroma_client_instance: Optional[chromadb.PersistentClient] = None
chroma_main_collection: Optional[chromadb.Collection] = None
embedding_fn: Optional[GeminiEmbeddingFunction] = None


def _init_collection(client: chromadb.PersistentClient, emb_fn: GeminiEmbeddingFunction, name: str) -> chromadb.Collection:
    """Obtiene o crea una colección; si hay conflicto de embedding la recrea vacía."""
    try:
        return client.get_or_create_collection(
            name=name,
            embedding_function=emb_fn,
            metadata={"hnsw:space": "cosine"},
        )
    except ValueError as e:
        if "conflict" in str(e).lower() or "embedding function" in str(e).lower():
            logger.warning(f"Conflicto de embedding en '{name}'. Recreando colección (se pierden los documentos anteriores)...")
            client.delete_collection(name)
            return client.create_collection(
                name=name,
                embedding_function=emb_fn,
                metadata={"hnsw:space": "cosine"},
            )
        raise


@asynccontextmanager
async def lifespan(app: FastAPI):
    global gemini_client, chroma_client_instance, chroma_main_collection, embedding_fn

    if not GEMINI_API_KEY:
        logger.error("GEMINI_API_KEY no configurada.")
    else:
        gemini_client = genai.Client(api_key=GEMINI_API_KEY)
        logger.info(f"Gemini configurado. Modelo: {GEMINI_MODEL} | Embedding: {GEMINI_EMBEDDING_MODEL}")

    try:
        chroma_client_instance = chromadb.PersistentClient(path=CHROMA_DB_PATH)
        embedding_fn = GeminiEmbeddingFunction()
        chroma_main_collection = _init_collection(chroma_client_instance, embedding_fn, "contrataciones_oece")
        logger.info(f"ChromaDB listo. Documentos: {chroma_main_collection.count()}")
    except Exception as e:
        logger.error(f"Error ChromaDB: {e}")

    yield
    logger.info("Servidor OECE-IA detenido.")


app = FastAPI(
    title="OECE-IA API",
    description="API del Asistente IA de Contrataciones Públicas - OECE Perú",
    version="3.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Modelos ──────────────────────────────────────────────────────────────────

class ConversationMessage(BaseModel):
    role: str = Field(..., pattern="^(user|assistant)$")
    content: str


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    user_id: str = Field(default="anonymous")
    case_id: str = Field(default="")
    conversation_history: list[ConversationMessage] = Field(default=[])


class ChatResponse(BaseModel):
    response: str
    sources: list[str] = []
    user_sources: list[str] = []
    documents_found: int = 0


class HealthResponse(BaseModel):
    status: str
    documents_in_db: int
    model: str


class DocumentInfoResponse(BaseModel):
    source: str
    chunks: int
    file_hash: Optional[str] = None


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _get_user_collection(user_id: str) -> Optional[chromadb.Collection]:
    if not chroma_client_instance or not embedding_fn:
        return None
    if not user_id or user_id == "anonymous":
        return None
    safe_uid = re.sub(r"[^a-zA-Z0-9_-]", "_", user_id)[:40]
    return _init_collection(chroma_client_instance, embedding_fn, f"u_{safe_uid}")


def _split_text(text: str) -> list[str]:
    if len(text) <= CHUNK_SIZE:
        return [text.strip()] if text.strip() else []
    chunks, start = [], 0
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


def _ingest_to_collection(collection, file_bytes, file_name, ext, extra_meta):
    fhash = _file_hash(file_bytes)
    existing = collection.get(where={"file_hash": fhash})
    if existing["ids"]:
        return {"message": f"'{file_name}' ya existe (sin cambios).", "chunks_added": 0, "source": file_name}

    with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as tmp:
        tmp.write(file_bytes)
        tmp_path = Path(tmp.name)
    try:
        text = _read_file(tmp_path)
    finally:
        tmp_path.unlink(missing_ok=True)

    if not text.strip():
        raise HTTPException(status_code=422, detail=f"'{file_name}' no tiene texto extraíble.")

    try:
        old = collection.get(where={"source": file_name})
        if old["ids"]:
            collection.delete(ids=old["ids"])
    except Exception:
        pass

    chunks = _split_text(text)
    ids = [str(uuid.uuid4()) for _ in chunks]
    metadatas = [
        {"source": file_name, "file_hash": fhash, "chunk_index": i, "total_chunks": len(chunks), **extra_meta}
        for i in range(len(chunks))
    ]
    collection.add(documents=chunks, ids=ids, metadatas=metadatas)
    return {"message": f"'{file_name}' ingestado.", "chunks_added": len(chunks), "source": file_name}


def _list_collection_docs(collection, where=None):
    if collection.count() == 0:
        return []
    kwargs = {"include": ["metadatas"]}
    if where:
        kwargs["where"] = where
    all_items = collection.get(**kwargs)
    sources: dict = {}
    for meta in all_items["metadatas"]:
        src = meta.get("source", "desconocido")
        if src not in sources:
            sources[src] = {"chunks": 0, "file_hash": meta.get("file_hash")}
        sources[src]["chunks"] += 1
    return [DocumentInfoResponse(source=s, chunks=i["chunks"], file_hash=i["file_hash"]) for s, i in sorted(sources.items())]


# ─── Llamadas a Gemini ────────────────────────────────────────────────────────

def _to_gemini_history(messages: list[dict]) -> list[types.Content]:
    history = []
    for msg in messages:
        role = "model" if msg["role"] == "assistant" else "user"
        history.append(types.Content(role=role, parts=[types.Part(text=msg["content"])]))
    return history


def _is_quota_error(e: Exception) -> bool:
    s = str(e).lower()
    return "429" in s or "quota" in s or "resource_exhausted" in s


async def _call_gemini(messages: list[dict], retries: int = 4) -> str:
    if not gemini_client:
        raise HTTPException(status_code=503, detail="GEMINI_API_KEY no configurada.")
    history = _to_gemini_history(messages[:-1])
    last_error: Exception = RuntimeError("Sin respuesta de Gemini")
    for attempt in range(retries):
        try:
            chat = gemini_client.aio.chats.create(
                model=GEMINI_MODEL,
                config=types.GenerateContentConfig(system_instruction=SYSTEM_PROMPT),
                history=history,
            )
            response = await chat.send_message(messages[-1]["content"])
            return response.text
        except Exception as e:
            last_error = e
            if _is_quota_error(e):
                wait = 15 * (2 ** attempt)  # 15s, 30s, 60s, 120s
                logger.warning(f"Gemini rate limit (intento {attempt + 1}/{retries}). Reintentando en {wait}s...")
                await asyncio.sleep(wait)
            else:
                break
    if _is_quota_error(last_error):
        raise HTTPException(
            status_code=429,
            detail="El servicio de IA está temporalmente saturado. Por favor espera unos minutos e intenta de nuevo.",
        )
    raise last_error


async def _stream_gemini(messages: list[dict]):
    if not gemini_client:
        yield "Error: GEMINI_API_KEY no configurada."
        return
    history = _to_gemini_history(messages[:-1])
    last_error: Exception = RuntimeError("Sin respuesta de Gemini")
    for attempt in range(3):
        try:
            chat = gemini_client.aio.chats.create(
                model=GEMINI_MODEL,
                config=types.GenerateContentConfig(system_instruction=SYSTEM_PROMPT),
                history=history,
            )
            async for chunk in await chat.send_message_stream(messages[-1]["content"]):
                if chunk.text:
                    yield chunk.text
            return
        except Exception as e:
            last_error = e
            if _is_quota_error(e) and attempt < 2:
                wait = 15 * (2 ** attempt)  # 15s, 30s
                logger.warning(f"Gemini stream rate limit (intento {attempt + 1}/3). Reintentando en {wait}s...")
                await asyncio.sleep(wait)
            else:
                break
    if _is_quota_error(last_error):
        raise HTTPException(
            status_code=429,
            detail="El servicio de IA está temporalmente saturado. Por favor espera unos minutos e intenta de nuevo.",
        )
    raise last_error


# ─── Endpoints ────────────────────────────────────────────────────────────────

@app.get("/health", response_model=HealthResponse)
async def health_check():
    doc_count = chroma_main_collection.count() if chroma_main_collection else 0
    return HealthResponse(status="ok", documents_in_db=doc_count, model=GEMINI_MODEL)


def _build_rag_context(request: ChatRequest) -> tuple[str, list[str], list[str], int]:
    context_text, sources, user_sources, documents_found = "", [], [], 0

    if chroma_main_collection and chroma_main_collection.count() > 0:
        try:
            results = chroma_main_collection.query(
                query_texts=[request.message],
                n_results=min(3, chroma_main_collection.count()),
                include=["documents", "metadatas", "distances"],
            )
            docs = results.get("documents", [[]])[0]
            metas = results.get("metadatas", [[]])[0]
            distances = results.get("distances", [[]])[0]
            relevant = [(d, m) for d, m, dist in zip(docs, metas, distances) if dist < 0.6]
            if relevant:
                documents_found += len(relevant)
                context_text = "\n\n---\n**INFORMACION DE LA BASE DE CONOCIMIENTOS OECE:**\n"
                for doc, meta in relevant:
                    source = meta.get("source", "Documento OECE")
                    page = meta.get("page", "")
                    context_text += f"\n*Fuente: {source}{f', pag. {page}' if page else ''}*\n{doc}\n"
                    label = f"{source}{f' (pag. {page})' if page else ''}"
                    if label not in sources:
                        sources.append(label)
        except Exception as e:
            logger.warning(f"Error RAG principal: {e}")

    user_col = _get_user_collection(request.user_id)
    if user_col and user_col.count() > 0:
        try:
            # Count only docs matching the case filter to avoid n_results > matches error
            if request.case_id:
                matching = user_col.get(where={"case_id": request.case_id})
                count_for_query = len(matching.get("ids", []))
            else:
                count_for_query = user_col.count()

            if count_for_query > 0:
                q_kwargs: dict = {
                    "query_texts": [request.message],
                    "n_results": min(3, count_for_query),
                    "include": ["documents", "metadatas", "distances"],
                }
                if request.case_id:
                    q_kwargs["where"] = {"case_id": request.case_id}
                u_results = user_col.query(**q_kwargs)
                u_docs = u_results.get("documents", [[]])[0]
                u_metas = u_results.get("metadatas", [[]])[0]
                u_distances = u_results.get("distances", [[]])[0]
                u_relevant = [(d, m) for d, m, dist in zip(u_docs, u_metas, u_distances) if dist < 0.65]
                if u_relevant:
                    documents_found += len(u_relevant)
                    context_text += "\n\n---\n**DOCUMENTOS PROPIOS DEL USUARIO:**\n"
                    for doc, meta in u_relevant:
                        source = meta.get("source", "Archivo personal")
                        context_text += f"\n*Archivo: {source}*\n{doc}\n"
                        if source not in user_sources:
                            user_sources.append(source)
        except Exception as e:
            logger.warning(f"Error RAG usuario: {e}")

    return context_text, sources, user_sources, documents_found


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    context_text, sources, user_sources, documents_found = _build_rag_context(request)
    messages = [{"role": m.role, "content": m.content} for m in request.conversation_history[-6:]]
    messages.append({"role": "user", "content": request.message + (context_text or "")})
    try:
        answer = await _call_gemini(messages)
        logger.info(f"Chat | user={request.user_id} | case={request.case_id} | docs={documents_found}")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error Gemini: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    return ChatResponse(response=answer, sources=sources, user_sources=user_sources, documents_found=documents_found)


@app.post("/chat/stream")
async def chat_stream(request: ChatRequest):
    context_text, sources, _, documents_found = _build_rag_context(request)
    messages = [{"role": m.role, "content": m.content} for m in request.conversation_history[-6:]]
    messages.append({"role": "user", "content": request.message + (context_text or "")})

    async def generate():
        try:
            async for token in _stream_gemini(messages):
                yield f"data: {json.dumps({'token': token}, ensure_ascii=False)}\n\n"
            yield f"data: {json.dumps({'done': True, 'sources': sources, 'documents_found': documents_found})}\n\n"
            logger.info(f"Stream | user={request.user_id} | docs={documents_found}")
        except Exception as e:
            logger.error(f"Error stream Gemini: {e}")
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")


@app.get("/stats")
async def get_stats():
    if not chroma_main_collection:
        return {"error": "Base de datos no disponible"}
    return {"total_documents": chroma_main_collection.count(), "collection_name": chroma_main_collection.name}


# ─── Admin ────────────────────────────────────────────────────────────────────

@app.get("/admin/documents", response_model=list[DocumentInfoResponse])
async def list_documents():
    if not chroma_main_collection:
        raise HTTPException(status_code=503, detail="Base de datos no disponible")
    return _list_collection_docs(chroma_main_collection)


@app.post("/admin/upload")
async def upload_document(file: UploadFile = File(...)):
    if not chroma_main_collection:
        raise HTTPException(status_code=503, detail="Base de datos no disponible")
    ext = Path(file.filename or "").suffix.lower()
    if ext not in {".pdf", ".docx", ".txt", ".md"}:
        raise HTTPException(status_code=400, detail=f"Formato no soportado: {ext}")
    file_bytes = await file.read()
    source_name = file.filename or f"documento_{uuid.uuid4().hex[:8]}{ext}"
    result = _ingest_to_collection(chroma_main_collection, file_bytes, source_name, ext, {})
    logger.info(f"Admin upload: '{source_name}' -> {result['chunks_added']} chunks")
    return result


@app.delete("/admin/document/{source_name}")
async def delete_document(source_name: str):
    if not chroma_main_collection:
        raise HTTPException(status_code=503, detail="Base de datos no disponible")
    try:
        results = chroma_main_collection.get(where={"source": source_name})
        if not results["ids"]:
            raise HTTPException(status_code=404, detail=f"Documento '{source_name}' no encontrado.")
        chroma_main_collection.delete(ids=results["ids"])
        return {"message": f"'{source_name}' eliminado.", "chunks_deleted": len(results["ids"])}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─── Usuario ──────────────────────────────────────────────────────────────────

@app.get("/user/documents", response_model=list[DocumentInfoResponse])
async def list_user_documents(user_id: str, case_id: str = ""):
    if not user_id or user_id == "anonymous":
        return []
    col = _get_user_collection(user_id)
    if not col or col.count() == 0:
        return []
    return _list_collection_docs(col, where={"case_id": case_id} if case_id else None)


@app.post("/user/upload")
async def upload_user_document(user_id: str = Form(...), case_id: str = Form(""), file: UploadFile = File(...)):
    if not user_id or user_id == "anonymous":
        raise HTTPException(status_code=400, detail="user_id requerido")
    ext = Path(file.filename or "").suffix.lower()
    if ext not in {".pdf", ".docx", ".txt", ".md"}:
        raise HTTPException(status_code=400, detail=f"Formato no soportado: {ext}")
    col = _get_user_collection(user_id)
    if not col:
        raise HTTPException(status_code=503, detail="Base de datos no disponible")
    file_bytes = await file.read()
    source_name = file.filename or f"archivo_{uuid.uuid4().hex[:8]}{ext}"
    result = _ingest_to_collection(col, file_bytes, source_name, ext, {"case_id": case_id, "user_id": user_id})
    logger.info(f"User upload: uid={user_id} case={case_id} '{source_name}' -> {result['chunks_added']} chunks")
    return result


@app.delete("/user/document/{source_name}")
async def delete_user_document(source_name: str, user_id: str):
    if not user_id or user_id == "anonymous":
        raise HTTPException(status_code=400, detail="user_id requerido")
    col = _get_user_collection(user_id)
    if not col:
        raise HTTPException(status_code=503, detail="Base de datos no disponible")
    try:
        results = col.get(where={"source": source_name})
        if not results["ids"]:
            raise HTTPException(status_code=404, detail=f"Archivo '{source_name}' no encontrado.")
        col.delete(ids=results["ids"])
        return {"message": f"'{source_name}' eliminado.", "chunks_deleted": len(results["ids"])}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
