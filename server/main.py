"""
OECE-IA - Servidor de IA para Contrataciones Públicas del Estado Peruano
Desarrollado con FastAPI + Gemini API (LLM + embeddings) + ChromaDB (RAG)
"""

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
import google.generativeai as genai
from chromadb import Documents, EmbeddingFunction, Embeddings
from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("oece-ia")

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.0-flash")
GEMINI_EMBEDDING_MODEL = os.getenv("GEMINI_EMBEDDING_MODEL", "models/text-embedding-004")
CHROMA_DB_PATH = os.getenv("CHROMA_DB_PATH", "./chroma_db")
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")
CHUNK_SIZE = 800
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

# ─── Embedding con Gemini ─────────────────────────────────────────────────────

class GeminiEmbeddingFunction(EmbeddingFunction):
    """Función de embedding usando Gemini text-embedding-004."""

    _BATCH_SIZE = 100  # límite de la API de Gemini

    def __call__(self, input: Documents) -> Embeddings:
        if not input:
            return []
        all_embeddings: Embeddings = []
        for i in range(0, len(input), self._BATCH_SIZE):
            batch = input[i : i + self._BATCH_SIZE]
            result = genai.embed_content(
                model=GEMINI_EMBEDDING_MODEL,
                content=batch,
                task_type="retrieval_document",
            )
            all_embeddings.extend(result["embedding"])
        return all_embeddings


# ─── Estado global ────────────────────────────────────────────────────────────
chroma_client_instance: Optional[chromadb.PersistentClient] = None
chroma_main_collection: Optional[chromadb.Collection] = None
embedding_fn: Optional[GeminiEmbeddingFunction] = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global chroma_client_instance, chroma_main_collection, embedding_fn

    if not GEMINI_API_KEY:
        logger.error("GEMINI_API_KEY no configurada. El servidor no podrá procesar solicitudes.")
    else:
        genai.configure(api_key=GEMINI_API_KEY)
        logger.info(f"Gemini API configurada. Modelo: {GEMINI_MODEL} | Embedding: {GEMINI_EMBEDDING_MODEL}")

    try:
        chroma_client_instance = chromadb.PersistentClient(path=CHROMA_DB_PATH)
        embedding_fn = GeminiEmbeddingFunction()
        chroma_main_collection = chroma_client_instance.get_or_create_collection(
            name="contrataciones_oece",
            embedding_function=embedding_fn,
            metadata={"hnsw:space": "cosine"},
        )
        logger.info(f"ChromaDB inicializado. Docs principales: {chroma_main_collection.count()}")
    except Exception as e:
        logger.error(f"Error ChromaDB: {e}")

    yield
    logger.info("Servidor OECE-IA detenido.")


app = FastAPI(
    title="OECE-IA API",
    description="API del Asistente IA de Contrataciones Públicas - OECE Perú",
    version="3.0.0",
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
    col_name = f"u_{safe_uid}"
    return chroma_client_instance.get_or_create_collection(
        name=col_name,
        embedding_function=embedding_fn,
        metadata={"hnsw:space": "cosine"},
    )


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


def _ingest_to_collection(
    collection: chromadb.Collection,
    file_bytes: bytes,
    file_name: str,
    ext: str,
    extra_meta: dict,
) -> dict:
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


def _list_collection_docs(collection: chromadb.Collection, where: Optional[dict] = None) -> list[DocumentInfoResponse]:
    total = collection.count()
    if total == 0:
        return []
    kwargs = {"include": ["metadatas"]}
    if where:
        kwargs["where"] = where
    all_items = collection.get(**kwargs)
    sources: dict[str, dict] = {}
    for meta in all_items["metadatas"]:
        src = meta.get("source", "desconocido")
        if src not in sources:
            sources[src] = {"chunks": 0, "file_hash": meta.get("file_hash")}
        sources[src]["chunks"] += 1
    return [DocumentInfoResponse(source=s, chunks=i["chunks"], file_hash=i["file_hash"]) for s, i in sorted(sources.items())]


# ─── Llamadas a Gemini ────────────────────────────────────────────────────────

def _build_gemini_history(messages: list[dict]) -> list[dict]:
    """Convierte el historial al formato de Gemini (user/model)."""
    history = []
    for msg in messages:
        role = "model" if msg["role"] == "assistant" else "user"
        history.append({"role": role, "parts": [msg["content"]]})
    return history


async def _call_gemini(messages: list[dict]) -> str:
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=503, detail="GEMINI_API_KEY no configurada.")
    model = genai.GenerativeModel(
        model_name=GEMINI_MODEL,
        system_instruction=SYSTEM_PROMPT,
    )
    history = _build_gemini_history(messages[:-1])
    chat = model.start_chat(history=history)
    response = await chat.send_message_async(messages[-1]["content"])
    return response.text


async def _stream_gemini(messages: list[dict]):
    """Generador async de tokens desde Gemini."""
    if not GEMINI_API_KEY:
        yield "Error: GEMINI_API_KEY no configurada."
        return
    model = genai.GenerativeModel(
        model_name=GEMINI_MODEL,
        system_instruction=SYSTEM_PROMPT,
    )
    history = _build_gemini_history(messages[:-1])
    chat = model.start_chat(history=history)
    async for chunk in await chat.send_message_async(messages[-1]["content"], stream=True):
        if chunk.text:
            yield chunk.text


# ─── Endpoints principales ────────────────────────────────────────────────────

@app.get("/health", response_model=HealthResponse)
async def health_check():
    doc_count = chroma_main_collection.count() if chroma_main_collection else 0
    return HealthResponse(status="ok", documents_in_db=doc_count, model=GEMINI_MODEL)


def _build_rag_context(request: ChatRequest) -> tuple[str, list[str], list[str], int]:
    """Consulta ChromaDB y devuelve contexto, fuentes y conteo de documentos."""
    context_text = ""
    sources: list[str] = []
    user_sources: list[str] = []
    documents_found = 0

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
            relevant = [(doc, meta) for doc, meta, dist in zip(docs, metas, distances) if dist < 0.6]
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
            q_kwargs: dict = {
                "query_texts": [request.message],
                "n_results": min(3, user_col.count()),
                "include": ["documents", "metadatas", "distances"],
            }
            if request.case_id:
                q_kwargs["where"] = {"case_id": request.case_id}
            user_results = user_col.query(**q_kwargs)
            u_docs = user_results.get("documents", [[]])[0]
            u_metas = user_results.get("metadatas", [[]])[0]
            u_distances = user_results.get("distances", [[]])[0]
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
    user_content = request.message + (context_text if context_text else "")
    messages.append({"role": "user", "content": user_content})

    try:
        answer = await _call_gemini(messages)
        logger.info(f"Chat | user={request.user_id} | case={request.case_id} | docs={documents_found}")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error Gemini: {e}")
        raise HTTPException(status_code=500, detail=f"Error al procesar: {str(e)}")

    return ChatResponse(response=answer, sources=sources, user_sources=user_sources, documents_found=documents_found)


@app.post("/chat/stream")
async def chat_stream(request: ChatRequest):
    """Endpoint SSE: devuelve tokens conforme Gemini los genera."""
    context_text, sources, _, documents_found = _build_rag_context(request)

    messages = [{"role": m.role, "content": m.content} for m in request.conversation_history[-6:]]
    user_content = request.message + (context_text if context_text else "")
    messages.append({"role": "user", "content": user_content})

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


# ─── Endpoints Admin (colección principal) ───────────────────────────────────

@app.get("/admin/documents", response_model=list[DocumentInfoResponse])
async def list_documents():
    if not chroma_main_collection:
        raise HTTPException(status_code=503, detail="Base de datos no disponible")
    return _list_collection_docs(chroma_main_collection)


@app.post("/admin/upload")
async def upload_document(file: UploadFile = File(...)):
    if not chroma_main_collection:
        raise HTTPException(status_code=503, detail="Base de datos no disponible")
    allowed_ext = {".pdf", ".docx", ".txt", ".md"}
    ext = Path(file.filename or "").suffix.lower()
    if ext not in allowed_ext:
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


# ─── Endpoints Usuario (colección personal) ───────────────────────────────────

@app.get("/user/documents", response_model=list[DocumentInfoResponse])
async def list_user_documents(user_id: str, case_id: str = ""):
    if not user_id or user_id == "anonymous":
        return []
    col = _get_user_collection(user_id)
    if not col or col.count() == 0:
        return []
    where = {"case_id": case_id} if case_id else None
    return _list_collection_docs(col, where=where)


@app.post("/user/upload")
async def upload_user_document(
    user_id: str = Form(...),
    case_id: str = Form(""),
    file: UploadFile = File(...),
):
    if not user_id or user_id == "anonymous":
        raise HTTPException(status_code=400, detail="user_id requerido")
    allowed_ext = {".pdf", ".docx", ".txt", ".md"}
    ext = Path(file.filename or "").suffix.lower()
    if ext not in allowed_ext:
        raise HTTPException(status_code=400, detail=f"Formato no soportado: {ext}")
    col = _get_user_collection(user_id)
    if not col:
        raise HTTPException(status_code=503, detail="Base de datos no disponible")
    file_bytes = await file.read()
    source_name = file.filename or f"archivo_{uuid.uuid4().hex[:8]}{ext}"
    extra = {"case_id": case_id, "user_id": user_id}
    result = _ingest_to_collection(col, file_bytes, source_name, ext, extra)
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
