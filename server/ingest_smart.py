"""
ingest_smart.py
Chunking consciente del tipo de documento, portado de rag-compras-publicas.

Para leyes/reglamentos: divide por Artículo (RE_ARTICULO).
Para directivas: divide por numeral (RE_NUMERAL).
Para otros documentos: divide por tamaño con solapamiento (fallback).

Cada chunk devuelve {"text": str, "meta": dict} donde meta incluye:
  categoria, tipo_referencia, referencia, articulo_num, articulo_titulo
"""

import re
import unicodedata

# ─── Constantes ───────────────────────────────────────────────────────────────
MAX_CHARS    = 1200
OVERLAP_CHARS = 200

# Encabezado real de artículo: "Artículo NN" al inicio de línea, seguido de delimitador.
RE_ARTICULO = re.compile(
    r'(?im)^[ \t]*art[ií]culo[ \t]+(\d+)[ \t]*[\.\-°ºª):…]+[ \t]*(.*)$'
)
# Numeral de directiva: "5", "5.2", "5.2.1" al inicio seguido de título en mayúscula.
RE_NUMERAL = re.compile(
    r'(?im)^[ \t]*(\d{1,2}(?:\.\d{1,2}){0,3})[ \t]*[\.\)]?[ \t]+([A-ZÁÉÍÓÚÑ].{2,150})$'
)
RE_DISPOSICION = re.compile(
    r'(?im)^[ \t]*(DISPOSICI[OÓ]N[ \t]+[A-ZÁÉÍÓÚÑ].{0,120})$'
)


# ─── Utilidades ───────────────────────────────────────────────────────────────

def _limpiar(texto: str) -> str:
    texto = texto.replace("\r\n", "\n")
    texto = re.sub(
        r'(?<=[A-Za-zÁÉÍÓÚÑáéíóúñ])[\-­]\n[ \t]*(?=[A-Za-zÁÉÍÓÚÑáéíóúñ])', '', texto
    )
    texto = re.sub(r'[ \t]+', ' ', texto)
    texto = re.sub(r'\n{3,}', '\n\n', texto)
    return texto.strip()


def _subdividir(texto: str, max_chars: int = MAX_CHARS, overlap: int = OVERLAP_CHARS) -> list[str]:
    if len(texto) <= max_chars:
        return [texto] if texto.strip() else []
    partes, inicio, n = [], 0, len(texto)
    while inicio < n:
        fin = min(inicio + max_chars, n)
        if fin < n:
            ventana = texto[inicio:fin]
            corte = max(ventana.rfind("\n\n"), ventana.rfind(". "), ventana.rfind("\n"))
            if corte > max_chars * 0.5:
                fin = inicio + corte + 1
        parte = texto[inicio:fin].strip()
        if parte:
            partes.append(parte)
        if fin >= n:
            break
        inicio = max(fin - overlap, inicio + 1)
    return partes


# ─── Detección de tipo de documento ──────────────────────────────────────────

def _detectar_categoria(source_name: str) -> str:
    s = source_name.lower()
    if re.search(r'(ley[\s\-_]*(general|32069|30225)|32069|30225|decreto.legislativo)', s):
        return "ley"
    if re.search(r'(reglamento|344.2018|009.202[45])', s):
        return "reglamento"
    if "directiva" in s:
        return "directiva"
    if re.search(r'opini[oó]n', s):
        return "opinion"
    return "general"


# ─── Troceo por artículo (leyes y reglamentos) ────────────────────────────────

def _trocear_por_articulo(texto: str, categoria: str) -> list[dict]:
    matches = list(RE_ARTICULO.finditer(texto))
    if not matches:
        return _trocear_por_tamano(texto, categoria)

    bloques = []
    # Preámbulo anterior al primer artículo
    pre = texto[:matches[0].start()].strip()
    if pre:
        for parte in _subdividir(pre):
            bloques.append({
                "text": parte,
                "meta": {
                    "categoria": categoria,
                    "tipo_referencia": "preambulo",
                    "referencia": "",
                    "articulo_num": "",
                    "articulo_titulo": "Preámbulo",
                },
            })

    for idx, m in enumerate(matches):
        ini = m.start()
        fin = matches[idx + 1].start() if idx + 1 < len(matches) else len(texto)
        cuerpo = texto[ini:fin].strip()
        art_num = m.group(1)
        art_titulo = (m.group(2) or "").strip()[:200]

        for parte in _subdividir(cuerpo):
            bloques.append({
                "text": parte,
                "meta": {
                    "categoria": categoria,
                    "tipo_referencia": "articulo",
                    "referencia": art_num,
                    "articulo_num": art_num,
                    "articulo_titulo": art_titulo,
                },
            })
    return bloques


# ─── Troceo por numeral (directivas) ─────────────────────────────────────────

def _trocear_por_numeral(texto: str, categoria: str) -> list[dict]:
    matches = list(RE_NUMERAL.finditer(texto)) + list(RE_DISPOSICION.finditer(texto))
    matches.sort(key=lambda m: m.start())
    if not matches:
        return _trocear_por_tamano(texto, categoria)

    bloques = []
    pre = texto[:matches[0].start()].strip()
    if pre:
        for parte in _subdividir(pre):
            bloques.append({
                "text": parte,
                "meta": {
                    "categoria": categoria,
                    "tipo_referencia": "preambulo",
                    "referencia": "",
                    "articulo_num": "",
                    "articulo_titulo": "Objeto / preámbulo",
                },
            })

    for idx, m in enumerate(matches):
        ini = m.start()
        fin = matches[idx + 1].start() if idx + 1 < len(matches) else len(texto)
        cuerpo = texto[ini:fin].strip()
        try:
            ref = m.group(1) if re.match(r'^\d', m.group(1) or '') else ""
            titulo = (m.group(2) or m.group(1) or "").strip()[:200]
        except IndexError:
            ref, titulo = "", (m.group(1) or "").strip()[:200]

        for parte in _subdividir(cuerpo):
            bloques.append({
                "text": parte,
                "meta": {
                    "categoria": categoria,
                    "tipo_referencia": "numeral",
                    "referencia": ref,
                    "articulo_num": ref,
                    "articulo_titulo": titulo,
                },
            })
    return bloques


# ─── Fallback: troceo por tamaño ─────────────────────────────────────────────

def _trocear_por_tamano(texto: str, categoria: str) -> list[dict]:
    return [
        {
            "text": parte,
            "meta": {
                "categoria": categoria,
                "tipo_referencia": "seccion",
                "referencia": "",
                "articulo_num": "",
                "articulo_titulo": "",
            },
        }
        for parte in _subdividir(texto)
    ]


# ─── Función pública ──────────────────────────────────────────────────────────

def smart_chunk(text: str, source_name: str) -> list[dict]:
    """
    Trocea `text` según el tipo de documento detectado por `source_name`.
    Devuelve lista de {"text": str, "meta": dict}.
    """
    texto = _limpiar(text)
    if not texto:
        return []

    categoria = _detectar_categoria(source_name)

    if categoria in ("ley", "reglamento"):
        bloques = _trocear_por_articulo(texto, categoria)
    elif categoria == "directiva":
        bloques = _trocear_por_numeral(texto, categoria)
    else:
        bloques = _trocear_por_tamano(texto, categoria)

    # Fallback defensivo: si no se generó ningún bloque, usar tamaño
    if not bloques:
        bloques = _trocear_por_tamano(texto, categoria)

    return bloques
