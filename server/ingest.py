"""
OECE-IA - Script de Ingestión de Documentos
============================================
Carga documentos (PDF, DOCX, TXT) en la base de datos vectorial (ChromaDB)
para que la IA pueda usarlos como contexto en las respuestas.

USO:
    python ingest.py                    # Ingesta todos los archivos en ./data/
    python ingest.py archivo.pdf        # Ingesta un archivo específico
    python ingest.py --clear            # Limpia la base y reinicia
    python ingest.py --list             # Lista los documentos en la base

FORMATOS SOPORTADOS: PDF, DOCX, TXT
"""

import argparse
import hashlib
import logging
import os
import sys
import uuid
from pathlib import Path

import chromadb
from chromadb.utils.embedding_functions import SentenceTransformerEmbeddingFunction
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("ingest")

CHROMA_DB_PATH = os.getenv("CHROMA_DB_PATH", "./chroma_db")
DATA_DIR = os.getenv("DATA_DIR", "./data")
CHUNK_SIZE = 800      # Caracteres por chunk
CHUNK_OVERLAP = 150   # Solapamiento entre chunks


# ─── Lectura de documentos ────────────────────────────────────────────────────

def read_pdf(path: Path) -> str:
    """Lee un PDF y extrae todo el texto."""
    try:
        import pdfplumber
        text_parts = []
        with pdfplumber.open(str(path)) as pdf:
            for i, page in enumerate(pdf.pages):
                text = page.extract_text()
                if text:
                    text_parts.append(f"[Página {i + 1}]\n{text.strip()}")
        return "\n\n".join(text_parts)
    except ImportError:
        logger.error("pdfplumber no instalado. Instala con: pip install pdfplumber")
        return ""
    except Exception as e:
        logger.error(f"Error al leer PDF {path}: {e}")
        return ""


def read_docx(path: Path) -> str:
    """Lee un archivo Word (.docx) y extrae el texto."""
    try:
        from docx import Document
        doc = Document(str(path))
        paragraphs = [p.text.strip() for p in doc.paragraphs if p.text.strip()]
        return "\n\n".join(paragraphs)
    except ImportError:
        logger.error("python-docx no instalado. Instala con: pip install python-docx")
        return ""
    except Exception as e:
        logger.error(f"Error al leer DOCX {path}: {e}")
        return ""


def read_txt(path: Path) -> str:
    """Lee un archivo de texto plano."""
    try:
        return path.read_text(encoding="utf-8", errors="ignore")
    except Exception as e:
        logger.error(f"Error al leer TXT {path}: {e}")
        return ""


def read_document(path: Path) -> str:
    """Detecta el tipo de archivo y lo lee."""
    ext = path.suffix.lower()
    if ext == ".pdf":
        return read_pdf(path)
    elif ext == ".docx":
        return read_docx(path)
    elif ext in (".txt", ".md"):
        return read_txt(path)
    else:
        logger.warning(f"Formato no soportado: {ext} ({path.name})")
        return ""


# ─── Chunking ─────────────────────────────────────────────────────────────────

def split_text(text: str, chunk_size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> list[str]:
    """Divide el texto en chunks con solapamiento."""
    if len(text) <= chunk_size:
        return [text]

    chunks = []
    start = 0
    while start < len(text):
        end = start + chunk_size

        # Busca un salto de línea o punto para no cortar a la mitad
        if end < len(text):
            for sep in ["\n\n", "\n", ". ", " "]:
                idx = text.rfind(sep, start, end)
                if idx > start + chunk_size // 2:
                    end = idx + len(sep)
                    break

        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        start = end - overlap

    return chunks


# ─── Ingestión ────────────────────────────────────────────────────────────────

def get_collection() -> chromadb.Collection:
    """Obtiene o crea la colección en ChromaDB."""
    chroma_client = chromadb.PersistentClient(path=CHROMA_DB_PATH)
    emb_fn = SentenceTransformerEmbeddingFunction(
        model_name="paraphrase-multilingual-MiniLM-L12-v2"
    )
    return chroma_client.get_or_create_collection(
        name="contrataciones_oece",
        embedding_function=emb_fn,
        metadata={"hnsw:space": "cosine"},
    )


def file_hash(path: Path) -> str:
    """Calcula el hash MD5 de un archivo para detectar duplicados."""
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def ingest_file(path: Path, collection: chromadb.Collection, force: bool = False) -> int:
    """
    Ingesta un archivo en ChromaDB.
    Retorna el número de chunks añadidos.
    """
    path = Path(path)
    if not path.exists():
        logger.error(f"Archivo no encontrado: {path}")
        return 0

    fhash = file_hash(path)
    source_name = path.name

    # Verificar si ya fue ingestado (por hash)
    if not force:
        existing = collection.get(where={"file_hash": fhash})
        if existing["ids"]:
            logger.info(f"'{source_name}' ya está en la base (hash: {fhash[:8]}...). Omitiendo.")
            return 0

    logger.info(f"Leyendo: {source_name}")
    text = read_document(path)

    if not text.strip():
        logger.warning(f"'{source_name}' no tiene texto extraíble.")
        return 0

    chunks = split_text(text)
    logger.info(f"'{source_name}' → {len(chunks)} chunks")

    # Eliminar versiones anteriores del mismo archivo (por nombre)
    try:
        old = collection.get(where={"source": source_name})
        if old["ids"]:
            collection.delete(ids=old["ids"])
            logger.info(f"Eliminada versión anterior: {len(old['ids'])} chunks")
    except Exception:
        pass

    # Añadir chunks nuevos
    ids = [str(uuid.uuid4()) for _ in chunks]
    metadatas = [
        {
            "source": source_name,
            "file_hash": fhash,
            "chunk_index": i,
            "total_chunks": len(chunks),
        }
        for i in range(len(chunks))
    ]

    collection.add(documents=chunks, ids=ids, metadatas=metadatas)
    logger.info(f"'{source_name}' ingestado: {len(chunks)} chunks añadidos.")
    return len(chunks)


def ingest_directory(data_dir: str = DATA_DIR, force: bool = False) -> None:
    """Ingesta todos los documentos en el directorio especificado."""
    data_path = Path(data_dir)
    if not data_path.exists():
        logger.error(f"Directorio no encontrado: {data_dir}")
        return

    supported = (".pdf", ".docx", ".txt", ".md")
    files = [f for f in data_path.iterdir() if f.suffix.lower() in supported]

    if not files:
        logger.warning(f"No se encontraron archivos en '{data_dir}'.")
        logger.info("Coloca tus archivos PDF, DOCX o TXT en la carpeta 'data/'")
        return

    logger.info(f"Encontrados {len(files)} archivos en '{data_dir}'")
    collection = get_collection()

    total_chunks = 0
    for f in sorted(files):
        total_chunks += ingest_file(f, collection, force=force)

    logger.info(f"\nIngestión completa. Total chunks añadidos: {total_chunks}")
    logger.info(f"Total documentos en la base: {collection.count()}")


def list_documents() -> None:
    """Lista los documentos que están en la base de datos."""
    collection = get_collection()
    total = collection.count()
    if total == 0:
        print("La base de datos está vacía. Usa 'python ingest.py' para cargar documentos.")
        return

    all_items = collection.get(include=["metadatas"])
    sources: dict[str, int] = {}
    for meta in all_items["metadatas"]:
        src = meta.get("source", "desconocido")
        sources[src] = sources.get(src, 0) + 1

    print(f"\nDocumentos en la base OECE-IA ({total} chunks total):")
    print("-" * 50)
    for src, count in sorted(sources.items()):
        print(f"  {src}: {count} chunks")
    print("-" * 50)


def clear_database() -> None:
    """Limpia completamente la base de datos vectorial."""
    confirm = input("¿Estás seguro de que deseas borrar TODA la base? (escribe 'SI' para confirmar): ")
    if confirm.strip().upper() != "SI":
        print("Operación cancelada.")
        return

    chroma_client = chromadb.PersistentClient(path=CHROMA_DB_PATH)
    try:
        chroma_client.delete_collection("contrataciones_oece")
        logger.info("Base de datos eliminada correctamente.")
    except Exception as e:
        logger.error(f"Error al eliminar colección: {e}")


# ─── CLI ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="OECE-IA - Ingestión de documentos en base vectorial"
    )
    parser.add_argument(
        "file",
        nargs="?",
        help="Ruta a un archivo específico para ingestar (PDF, DOCX, TXT)",
    )
    parser.add_argument(
        "--clear",
        action="store_true",
        help="Limpia toda la base de datos vectorial",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="Lista los documentos en la base de datos",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-ingesta aunque el archivo ya exista",
    )
    parser.add_argument(
        "--dir",
        default=DATA_DIR,
        help=f"Directorio a ingestar (default: {DATA_DIR})",
    )

    args = parser.parse_args()

    if args.clear:
        clear_database()
    elif args.list:
        list_documents()
    elif args.file:
        collection = get_collection()
        ingest_file(Path(args.file), collection, force=args.force)
        logger.info(f"Total en base: {collection.count()}")
    else:
        ingest_directory(data_dir=args.dir, force=args.force)
