"""
OECE-IA - Script de Ingestión de Documentos
============================================
Carga documentos (PDF, DOCX, TXT) en ChromaDB usando Gemini text-embedding-004.

USO:
    python ingest.py                    # Ingesta todos los archivos en ./data/
    python ingest.py archivo.pdf        # Ingesta un archivo específico
    python ingest.py --clear            # Limpia la base y reinicia
    python ingest.py --list             # Lista los documentos en la base
"""

import argparse
import hashlib
import logging
import os
import sys
import uuid
from pathlib import Path

import chromadb
from chromadb import Documents, EmbeddingFunction, Embeddings
from dotenv import load_dotenv
from google import genai
from google.genai import types

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("ingest")

GEMINI_API_KEY         = os.getenv("GEMINI_API_KEY", "")
GEMINI_EMBEDDING_MODEL = os.getenv("GEMINI_EMBEDDING_MODEL", "models/text-embedding-004")
CHROMA_DB_PATH         = os.getenv("CHROMA_DB_PATH", "./chroma_db")
DATA_DIR               = os.getenv("DATA_DIR", "./data")
CHUNK_SIZE   = 800
CHUNK_OVERLAP = 150

if not GEMINI_API_KEY:
    logger.error("GEMINI_API_KEY no configurada.")
    sys.exit(1)

client = genai.Client(api_key=GEMINI_API_KEY)


# ─── Embedding ────────────────────────────────────────────────────────────────

class GeminiEmbeddingFunction(EmbeddingFunction):
    _BATCH_SIZE = 100

    def __call__(self, input: Documents) -> Embeddings:
        if not input:
            return []
        all_embeddings: Embeddings = []
        for i in range(0, len(input), self._BATCH_SIZE):
            batch = list(input[i : i + self._BATCH_SIZE])
            result = client.models.embed_content(
                model=GEMINI_EMBEDDING_MODEL,
                contents=batch,
                config=types.EmbedContentConfig(task_type="RETRIEVAL_DOCUMENT"),
            )
            all_embeddings.extend([e.values for e in result.embeddings])
        return all_embeddings


# ─── Lectura de documentos ────────────────────────────────────────────────────

def read_document(path: Path) -> str:
    ext = path.suffix.lower()
    if ext == ".pdf":
        try:
            import pdfplumber
            parts = []
            with pdfplumber.open(str(path)) as pdf:
                for i, page in enumerate(pdf.pages):
                    text = page.extract_text()
                    if text:
                        parts.append(f"[Página {i + 1}]\n{text.strip()}")
            return "\n\n".join(parts)
        except Exception as e:
            logger.error(f"Error leyendo PDF {path}: {e}")
            return ""
    elif ext == ".docx":
        try:
            from docx import Document
            doc = Document(str(path))
            return "\n\n".join(p.text.strip() for p in doc.paragraphs if p.text.strip())
        except Exception as e:
            logger.error(f"Error leyendo DOCX {path}: {e}")
            return ""
    elif ext in (".txt", ".md"):
        return path.read_text(encoding="utf-8", errors="ignore")
    logger.warning(f"Formato no soportado: {path.suffix}")
    return ""


def split_text(text: str) -> list[str]:
    if len(text) <= CHUNK_SIZE:
        return [text]
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


# ─── Colección ────────────────────────────────────────────────────────────────

def get_collection() -> chromadb.Collection:
    chroma_client = chromadb.PersistentClient(path=CHROMA_DB_PATH)
    emb_fn = GeminiEmbeddingFunction()
    try:
        return chroma_client.get_or_create_collection(
            name="contrataciones_oece",
            embedding_function=emb_fn,
            metadata={"hnsw:space": "cosine"},
        )
    except ValueError as e:
        if "conflict" in str(e).lower() or "embedding function" in str(e).lower():
            logger.warning("Conflicto de embedding. Recreando colección...")
            chroma_client.delete_collection("contrataciones_oece")
            return chroma_client.create_collection(
                name="contrataciones_oece",
                embedding_function=emb_fn,
                metadata={"hnsw:space": "cosine"},
            )
        raise


def file_hash(path: Path) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def ingest_file(path: Path, collection: chromadb.Collection, force: bool = False) -> int:
    if not path.exists():
        logger.error(f"Archivo no encontrado: {path}")
        return 0

    fhash = file_hash(path)
    source_name = path.name

    if not force:
        existing = collection.get(where={"file_hash": fhash})
        if existing["ids"]:
            logger.info(f"'{source_name}' ya está en la base. Omitiendo.")
            return 0

    text = read_document(path)
    if not text.strip():
        logger.warning(f"'{source_name}' no tiene texto extraíble.")
        return 0

    chunks = split_text(text)
    logger.info(f"'{source_name}' → {len(chunks)} chunks — generando embeddings con Gemini...")

    try:
        old = collection.get(where={"source": source_name})
        if old["ids"]:
            collection.delete(ids=old["ids"])
    except Exception:
        pass

    ids = [str(uuid.uuid4()) for _ in chunks]
    metadatas = [{"source": source_name, "file_hash": fhash, "chunk_index": i, "total_chunks": len(chunks)} for i in range(len(chunks))]
    collection.add(documents=chunks, ids=ids, metadatas=metadatas)
    logger.info(f"'{source_name}' ingestado: {len(chunks)} chunks.")
    return len(chunks)


def ingest_directory(data_dir: str = DATA_DIR, force: bool = False) -> None:
    data_path = Path(data_dir)
    if not data_path.exists():
        logger.error(f"Directorio no encontrado: {data_dir}")
        return
    files = [f for f in data_path.iterdir() if f.suffix.lower() in (".pdf", ".docx", ".txt", ".md")]
    if not files:
        logger.warning(f"No se encontraron archivos en '{data_dir}'.")
        return
    collection = get_collection()
    total = sum(ingest_file(f, collection, force=force) for f in sorted(files))
    logger.info(f"Ingestión completa. Chunks añadidos: {total} | Total en base: {collection.count()}")


def list_documents() -> None:
    collection = get_collection()
    if collection.count() == 0:
        print("Base vacía.")
        return
    sources: dict[str, int] = {}
    for meta in collection.get(include=["metadatas"])["metadatas"]:
        src = meta.get("source", "desconocido")
        sources[src] = sources.get(src, 0) + 1
    print(f"\nDocumentos ({collection.count()} chunks total):")
    for src, count in sorted(sources.items()):
        print(f"  {src}: {count} chunks")


def clear_database() -> None:
    if input("¿Borrar TODA la base? (escribe 'SI'): ").strip().upper() != "SI":
        print("Cancelado.")
        return
    chroma_client = chromadb.PersistentClient(path=CHROMA_DB_PATH)
    try:
        chroma_client.delete_collection("contrataciones_oece")
        logger.info("Base eliminada.")
    except Exception as e:
        logger.error(f"Error: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="OECE-IA - Ingestión de documentos")
    parser.add_argument("file", nargs="?", help="Archivo a ingestar")
    parser.add_argument("--clear", action="store_true")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dir", default=DATA_DIR)
    args = parser.parse_args()

    if args.clear:
        clear_database()
    elif args.list:
        list_documents()
    elif args.file:
        col = get_collection()
        ingest_file(Path(args.file), col, force=args.force)
    else:
        ingest_directory(data_dir=args.dir, force=args.force)
