"""
OECE-IA - Servidor de IA para Contrataciones Públicas del Estado Peruano
FastAPI + Gemini API + ChromaDB (RAG)

Fusión con rag-compras-publicas (M. Orellana):
  - Verificación de citas (citas.py)
  - Instrucciones de estructura, precisión, jerarquía, cruce y registro
  - Jerarquía de autoridad en reranking: Ley > Reglamento > Directivas > Opiniones
  - Preguntas sugeridas post-respuesta
  - Ley N° 32069 + DS 009-2025-EF como normativa principal
"""

import asyncio
import hashlib
import logging
import os
import re
import json
import tempfile
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

import chromadb
import requests as http_requests
from chromadb import Documents, EmbeddingFunction, Embeddings
from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from google import genai
from google.genai import types
from pydantic import BaseModel, Field

from citas import verificar_citas

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("oece-ia")

GEMINI_API_KEY         = os.getenv("GEMINI_API_KEY", "")
GEMINI_MODEL           = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
GEMINI_EMBEDDING_MODEL = os.getenv("GEMINI_EMBEDDING_MODEL", "text-embedding-004")
CHROMA_DB_PATH         = os.getenv("CHROMA_DB_PATH", "./chroma_db")
ALLOWED_ORIGINS        = os.getenv("ALLOWED_ORIGINS", "*").split(",")
CHUNK_SIZE    = 800
CHUNK_OVERLAP = 150

# ─── Jerarquía de autoridad (menor índice = mayor autoridad) ─────────────────
_ORDEN_AUTORIDAD = ("ley", "reglamento", "directiva", "opinion", "general")
_PESO_AUTORIDAD  = {cat: round(0.05 * i, 3) for i, cat in enumerate(_ORDEN_AUTORIDAD)}


def _categoria_de_fuente(source: str) -> str:
    s = source.lower()
    if re.search(r'(ley[\s\-_]*(general|32069|30225)|32069|30225|decreto.legislativo)', s):
        return "ley"
    if re.search(r'(reglamento|344.2018|009.202[45])', s):
        return "reglamento"
    if "directiva" in s:
        return "directiva"
    if re.search(r'opini[oó]n', s):
        return "opinion"
    return "general"


def _nombre_legible(source: str) -> str:
    s = source.lower()
    if re.search(r'ley.general.*contratac|32069', s) and "reglamento" not in s:
        return "Ley N° 32069"
    if re.search(r'reglamento.*(32069|009.2025|009.2024)', s) or re.search(r'009.202[45].*ef', s):
        return "Reglamento (DS 009-2025-EF)"
    if "30225" in s and "reglamento" not in s:
        return "Ley N° 30225"
    if "344-2018" in s or "344_2018" in s:
        return "Reglamento (DS 344-2018-EF)"
    name = re.sub(r'\.(pdf|docx|txt|md)$', '', source, flags=re.IGNORECASE)
    name = re.sub(r'^\d+[-_]', '', name)
    name = name.replace('-', ' ').replace('_', ' ').strip()
    return name[:80] if name else source


def _formato_cita(meta: dict) -> str:
    source   = meta.get("source", "Documento")
    tipo     = meta.get("tipo_referencia", "")
    ref      = meta.get("referencia", "") or meta.get("articulo_num", "")
    nombre   = _nombre_legible(source)
    if tipo == "articulo" and ref:
        return f"{nombre}, Art. {ref}"
    if tipo == "numeral" and ref:
        return f"{nombre}, Num. {ref}"
    if tipo == "opinion" and ref:
        return f"Opinión {ref}"
    if ref:
        return f"{nombre}, {ref}"
    return nombre


# ─── System prompt + instrucciones (fusión con rag-compras-publicas) ─────────

GUARDRAIL = (
    "Tu ÚNICA fuente de verdad es el contexto normativo que se te proporciona. "
    "Tienes estrictamente prohibido usar conocimiento previo o externo no incluido en ese contexto. "
    "Si la respuesta no se encuentra en el contexto, responde textualmente: "
    "\"De acuerdo con el marco normativo cargado en el sistema, no dispongo de la información "
    "exacta para responder a esta consulta\". No asumas, no deduzcas plazos y no inventes artículos."
)

INSTRUCCION_CITAS = (
    "FORMATO DE CITAS: tras cada afirmación, coloca el marcador [N] del/los fragmento(s) "
    "recuperados que la respaldan. Ejemplo: 'El plazo es de cinco días hábiles [1].' "
    "Usa solo números de fragmentos existentes; no inventes marcadores."
)

INSTRUCCION_PRECISION = (
    "PRECISIÓN: si el usuario cita una norma de forma imprecisa pero el contexto SÍ contiene "
    "la norma pertinente, RESPONDE con base en el contexto y ACLARA la referencia correcta. "
    "Recurre al 'no dispongo' SOLO cuando el contexto realmente no la contenga."
)

INSTRUCCION_JERARQUIA = (
    "JERARQUÍA AL RESPONDER: estructura la respuesta apoyándote PRIMERO en la fuente de mayor "
    "autoridad (Ley → Reglamento → Directivas → Opiniones/Resoluciones). Las opiniones y "
    "resoluciones son apoyo o aclaración; no deben ser la fuente principal cuando hay Ley o "
    "Reglamento aplicable en el contexto."
)

INSTRUCCION_ESTRUCTURA = (
    "ESTRUCTURA Y COMPLETITUD:\n"
    "1. ENCUADRE: abre situando la figura en su marco normativo (Ley y Reglamento).\n"
    "2. ENUMERA LO QUE LA NORMA ENUMERA: si hay una lista taxativa en el contexto, "
    "reprodúcela COMPLETA; prohibido resumir con 'entre otros' o '...' si los ítems están.\n"
    "3. LISTAS CON GLOSA: presenta enumeraciones como lista con breve explicación de cada ítem.\n"
    "4. QUIÉN DECIDE: cuando la norma asigne una competencia, nómbrala explícitamente.\n"
    "5. LIMITACIONES Y EXCEPCIONES: nómbralas concretas, no las insinúes.\n"
    "6. SIN BLOQUE FINAL DE REFERENCIAS: el sistema muestra automáticamente las fuentes citadas; "
    "no agregues un bloque 'Referencias' al final. Los marcadores [N] en línea SÍ se mantienen."
)

INSTRUCCION_CRUCE = (
    "CRUCE LEY-REGLAMENTO: si en el contexto hay artículos de la Ley Y del Reglamento sobre el "
    "mismo tema, menciona ambos indicando la relación ('regulado en Art. X de la Ley [n] y "
    "desarrollado en Art. Y del Reglamento [n]'). Solo cruza normas PRESENTES en el contexto."
)

INSTRUCCION_REGISTRO = (
    "REGISTRO: formal, técnico-legal, apto para un informe institucional. Usa negritas (**...**) "
    "para ideas fuerza y términos clave. NO uses emojis. Adapta la extensión a la complejidad."
)

SYSTEM_PROMPT = f"""Eres **OECE-IA**, el asistente virtual oficial especializado en contrataciones públicas del Estado peruano.

## Marco normativo vigente (2025)
- **Ley N° 32069** — Ley General de Contrataciones Públicas (nueva ley vigente desde 2024)
- **DS 009-2025-EF** — Reglamento de la Ley N° 32069
- **Ley N° 30225** y modificatorias (DL 1341, DL 1444, DL 1471) — para procesos en transición
- **DS 344-2018-EF** — Reglamento anterior (aplicable a procesos iniciados bajo Ley 30225)
- **Contrataciones Menores (≤ 8 UIT)** — Art. 5 de la Ley 32069 y directivas OECE vigentes
- Directivas, opiniones y resoluciones del Tribunal de Contrataciones del Estado (TCP)

## Temas que cubres
- Ley 32069 y DS 009-2025-EF (procedimientos, plazos, requisitos, sanciones)
- Ley 30225 y DS 344-2018-EF (procesos en transición)
- Contrataciones menores: requisitos, excepciones, proceso
- Procedimientos de selección: Licitación Pública, Concurso Público, Adjudicación Simplificada, Subasta Inversa, Contratación Directa, Comparación de Precios
- SEACE, RNP, TDR, expedientes técnicos, ejecución contractual
- Infracciones, sanciones y resoluciones del TCP
- **Análisis de documentos propios del usuario** (contratos, bases, TDR, actas, etc.)

## Reglas
{GUARDRAIL}

1. Responde consultas de contrataciones públicas. Si el tema es completamente ajeno, responde: *"Mi especialidad es el sistema de contrataciones públicas. ¿Tienes alguna consulta en ese ámbito?"*
2. Cuando el usuario haya subido documentos a su caso, analízalos y responde sobre su contenido.
3. Usa formato Markdown (negritas, listas, tablas cuando aplique).

## Contacto OECE
- Web: www.gob.pe/oece | SEACE: seace.gob.pe | Soporte: WhatsApp +51 910 561 256
"""


# ─── Instrucciones de sugerencias ────────────────────────────────────────────
INSTRUCCION_SUGERENCIAS = (
    "A partir de la consulta y la respuesta dada, propón EXACTAMENTE 3 preguntas de "
    "PROFUNDIZACIÓN sobre el MISMO tema normativo. Requisitos: (a) que profundice sin repetir "
    "lo ya respondido; (b) respondible con la Ley 32069, su Reglamento o directivas OECE; "
    "(c) en español, clara, breve y autocontenida. "
    "Devuelve ÚNICAMENTE un arreglo JSON de 3 cadenas, sin texto adicional. "
    'Ejemplo: ["¿...?", "¿...?", "¿...?"]'
)


# ─── Cliente Gemini global ────────────────────────────────────────────────────
gemini_client: Optional[genai.Client] = None


class GeminiEmbeddingFunction(EmbeddingFunction):
    _BATCH_SIZE = 20

    def __call__(self, input: Documents) -> Embeddings:
        if not input or not GEMINI_API_KEY:
            return []
        all_embeddings: Embeddings = []
        url = (
            f"https://generativelanguage.googleapis.com/v1beta/models/"
            f"{GEMINI_EMBEDDING_MODEL}:embedContent?key={GEMINI_API_KEY}"
        )
        for text in input:
            try:
                resp = http_requests.post(
                    url,
                    json={
                        "model": f"models/{GEMINI_EMBEDDING_MODEL}",
                        "content": {"parts": [{"text": str(text)}]},
                        "taskType": "RETRIEVAL_DOCUMENT",
                    },
                    timeout=30,
                )
                resp.raise_for_status()
                all_embeddings.append(resp.json()["embedding"]["values"])
            except Exception as e:
                logger.error(f"Error embedding texto: {e}")
                all_embeddings.append([0.0] * 768)
        return all_embeddings


chroma_client_instance: Optional[chromadb.PersistentClient] = None
chroma_main_collection: Optional[chromadb.Collection] = None
embedding_fn: Optional[GeminiEmbeddingFunction] = None


def _init_collection(client: chromadb.PersistentClient, emb_fn: GeminiEmbeddingFunction, name: str) -> chromadb.Collection:
    try:
        return client.get_or_create_collection(
            name=name,
            embedding_function=emb_fn,
            metadata={"hnsw:space": "cosine"},
        )
    except ValueError as e:
        if "conflict" in str(e).lower() or "embedding function" in str(e).lower():
            logger.warning(f"Conflicto de embedding en '{name}'. Recreando colección...")
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
        logger.info(f"Gemini: {GEMINI_MODEL} | Embedding: {GEMINI_EMBEDDING_MODEL}")

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
    version="4.0.0",
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
    suggested_questions: list[str] = []


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

    # Chunking consciente del tipo (artículos para leyes/reglamentos)
    from ingest_smart import smart_chunk
    chunks_data = smart_chunk(text, file_name)

    ids = [str(uuid.uuid4()) for _ in chunks_data]
    metadatas = []
    for i, cd in enumerate(chunks_data):
        meta = {
            "source": file_name,
            "file_hash": fhash,
            "chunk_index": i,
            "total_chunks": len(chunks_data),
            **cd.get("meta", {}),
            **extra_meta,
        }
        metadatas.append(meta)

    documents = [cd["text"] for cd in chunks_data]
    collection.add(documents=documents, ids=ids, metadatas=metadatas)
    return {"message": f"'{file_name}' ingestado.", "chunks_added": len(chunks_data), "source": file_name}


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
                wait = 15 * (2 ** attempt)
                logger.warning(f"Gemini rate limit (intento {attempt + 1}/{retries}). Esperando {wait}s...")
                await asyncio.sleep(wait)
            else:
                break
    if _is_quota_error(last_error):
        raise HTTPException(
            status_code=429,
            detail="El servicio de IA está temporalmente saturado. Por favor espera unos minutos.",
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
                wait = 15 * (2 ** attempt)
                logger.warning(f"Gemini stream rate limit (intento {attempt + 1}/3). Esperando {wait}s...")
                await asyncio.sleep(wait)
            else:
                break
    if _is_quota_error(last_error):
        raise HTTPException(status_code=429, detail="Servicio saturado. Espera unos minutos.")
    raise last_error


async def _generar_sugerencias(pregunta: str, respuesta: str) -> list[str]:
    """Genera 3 preguntas de profundización (llamada aislada, no afecta la respuesta)."""
    if not gemini_client or not respuesta.strip():
        return []
    try:
        prompt = (
            INSTRUCCION_SUGERENCIAS + "\n\n"
            f"CONSULTA DEL USUARIO:\n{pregunta.strip()}\n\n"
            f"RESPUESTA DADA:\n{respuesta.strip()[:4000]}"
        )
        chat = gemini_client.aio.chats.create(
            model=GEMINI_MODEL,
            config=types.GenerateContentConfig(temperature=0.4),
            history=[],
        )
        resp = await chat.send_message(prompt)
        text = (resp.text or "").strip()
        text = re.sub(r'^```(?:json)?\s*|\s*```$', '', text, flags=re.IGNORECASE)
        m = re.search(r'\[.*\]', text, flags=re.DOTALL)
        if m:
            datos = json.loads(m.group(0))
            if isinstance(datos, list):
                return [str(x).strip() for x in datos if str(x).strip()][:3]
    except Exception:
        pass
    return []


# ─── RAG context ─────────────────────────────────────────────────────────────

def _build_rag_context(request: "ChatRequest") -> tuple[str, list[str], list[str], int]:
    context_text, sources, user_sources, documents_found = "", [], [], 0

    if chroma_main_collection and chroma_main_collection.count() > 0:
        try:
            results = chroma_main_collection.query(
                query_texts=[request.message],
                n_results=min(8, chroma_main_collection.count()),
                include=["documents", "metadatas", "distances"],
            )
            docs      = results.get("documents", [[]])[0]
            metas     = results.get("metadatas", [[]])[0]
            distances = results.get("distances", [[]])[0]

            # Rerank por jerarquía de autoridad (Ley > Reglamento > Directiva > Opinión)
            candidates = [
                (d, m, dist)
                for d, m, dist in zip(docs, metas, distances)
                if dist < 0.65
            ]
            candidates.sort(
                key=lambda t: t[2] + _PESO_AUTORIDAD.get(
                    t[1].get("categoria") or _categoria_de_fuente(t[1].get("source", "")),
                    0.10
                )
            )
            relevant = candidates[:5]

            if relevant:
                documents_found += len(relevant)
                context_text = (
                    "\n\n---\n"
                    "**CONTEXTO NORMATIVO (cita cada fragmento con [N] en tu respuesta):**\n"
                )
                for i, (doc, meta, _dist) in enumerate(relevant, 1):
                    cita = _formato_cita(meta)
                    context_text += f"\n**[{i}]** *{cita}*\n{doc}\n"
                    if cita not in sources:
                        sources.append(cita)
        except Exception as e:
            logger.warning(f"Error RAG principal: {e}")

    user_col = _get_user_collection(request.user_id)
    if user_col and user_col.count() > 0:
        try:
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
                u_docs      = u_results.get("documents", [[]])[0]
                u_metas     = u_results.get("metadatas", [[]])[0]
                u_distances = u_results.get("distances", [[]])[0]
                u_relevant  = [
                    (d, m) for d, m, dist in zip(u_docs, u_metas, u_distances)
                    if dist < 0.65
                ]
                if u_relevant:
                    documents_found += len(u_relevant)
                    user_offset = len(sources) + 1
                    context_text += (
                        "\n\n---\n"
                        "**DOCUMENTOS PROPIOS DEL USUARIO (cita con [N]):**\n"
                    )
                    for i, (doc, meta) in enumerate(u_relevant, user_offset):
                        source = meta.get("source", "Archivo personal")
                        context_text += f"\n**[{i}]** *Archivo: {source}*\n{doc}\n"
                        if source not in user_sources:
                            user_sources.append(source)
        except Exception as e:
            logger.warning(f"Error RAG usuario: {e}")

    return context_text, sources, user_sources, documents_found


def _build_prompt(message: str, context_text: str) -> str:
    instructions = "\n\n".join([
        GUARDRAIL,
        INSTRUCCION_PRECISION,
        INSTRUCCION_JERARQUIA,
        INSTRUCCION_ESTRUCTURA,
        INSTRUCCION_CRUCE,
        INSTRUCCION_CITAS,
        INSTRUCCION_REGISTRO,
    ])
    if context_text:
        return f"{context_text}\n\n{instructions}\n\nCONSULTA DEL USUARIO:\n{message}"
    return message


# ─── Endpoints ────────────────────────────────────────────────────────────────

@app.get("/health", response_model=HealthResponse)
async def health_check():
    doc_count = chroma_main_collection.count() if chroma_main_collection else 0
    return HealthResponse(status="ok", documents_in_db=doc_count, model=GEMINI_MODEL)


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    context_text, sources, user_sources, documents_found = _build_rag_context(request)
    messages = [{"role": m.role, "content": m.content} for m in request.conversation_history[-6:]]
    messages.append({"role": "user", "content": _build_prompt(request.message, context_text)})
    try:
        answer = await _call_gemini(messages)
        logger.info(f"Chat | user={request.user_id} | case={request.case_id} | docs={documents_found}")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error Gemini: {e}")
        raise HTTPException(status_code=500, detail=str(e))

    # Verificar y limpiar citas alucinadas
    check = verificar_citas(answer, documents_found)
    answer = check["respuesta_limpia"]
    if check["citas_invalidas"]:
        logger.warning(f"Citas inventadas neutralizadas: {check['citas_invalidas']}")

    # Preguntas sugeridas (llamada aislada, no bloquea la respuesta)
    suggested = await _generar_sugerencias(request.message, answer)

    return ChatResponse(
        response=answer,
        sources=sources,
        user_sources=user_sources,
        documents_found=documents_found,
        suggested_questions=suggested,
    )


@app.post("/chat/stream")
async def chat_stream(request: ChatRequest):
    context_text, sources, _, documents_found = _build_rag_context(request)
    messages = [{"role": m.role, "content": m.content} for m in request.conversation_history[-6:]]
    messages.append({"role": "user", "content": _build_prompt(request.message, context_text)})

    async def generate():
        full_response = []
        try:
            async for token in _stream_gemini(messages):
                full_response.append(token)
                yield f"data: {json.dumps({'token': token}, ensure_ascii=False)}\n\n"

            # Verificar citas al finalizar
            complete = "".join(full_response)
            check = verificar_citas(complete, documents_found)
            if check["citas_invalidas"]:
                logger.warning(f"Stream — citas neutralizadas: {check['citas_invalidas']}")

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
