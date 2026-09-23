"""
citas.py
-------------------------------------------------------------------
Chequeo de FIDELIDAD de citas (determinista, barato, SIN LLM).

Regla: un numero N citado es valido solo si
    1 <= N <= n_fragmentos
(los fragmentos efectivamente recuperados que se mostraron al modelo).
Un N fuera de rango es una cita INVENTADA: se neutraliza para no
enganar al lector, sin borrar la frase que lo contiene.

IMPORTANTE — marcadores AGRUPADOS: un marcador puede ser suelto ("[6]") o
AGRUPADO ("[6, 7, 8]"). Se inspecciona CADA numero del marcador, tambien los
que van dentro de un grupo. Un numero citado solo-dentro-de-un-grupo cuenta
como CITADO igual que uno suelto (antes el regex solo veia los sueltos y esos
numeros se juzgaban erroneamente "no citados", con dos consecuencias graves
aguas abajo: sus fuentes se borraban del filtro fantasma y sus marcadores
quedaban huerfanos o —peor— apuntando a la fuente equivocada).

Corre en cada respuesta de produccion: cero llamadas a la red.
-------------------------------------------------------------------
"""
import re

# Marcador de cita: un numero suelto ("[6]") o un GRUPO de numeros ("[6, 7, 8]").
_RE_MARCADOR = re.compile(r"\[\s*\d+(?:\s*,\s*\d+)*\s*\]")
MARCA_INVALIDA = "[cita no verificada]"


def verificar_citas(respuesta, n_fragmentos):
    """Valida los marcadores [N] (sueltos y AGRUPADOS) de `respuesta` contra
    `n_fragmentos` recuperados.

    Devuelve un dict:
      - respuesta_limpia: la respuesta con los numeros INVALIDOS neutralizados.
        En un marcador agrupado se descartan solo los numeros fuera de rango y se
        conservan los validos ("[3, 99]" -> "[3]"); un marcador cuyos numeros son
        TODOS invalidos se reemplaza por una marca discreta (la frase se conserva).
        Un marcador enteramente valido se deja EXACTAMENTE como estaba.
      - citas_validas:   list[int] ordenada de N unicos en rango [1, n_fragmentos]
        (incluye los citados dentro de un grupo).
      - citas_invalidas: list[int] ordenada de N unicos fuera de rango (inventados).
      - ok:              True si no se hallo ninguna cita inventada.
    """
    texto = respuesta or ""
    validas, invalidas = set(), set()

    def _sustituir(m):
        nums = [int(x) for x in re.findall(r"\d+", m.group(0))]
        vals, vistos = [], set()
        for n in nums:
            if 1 <= n <= n_fragmentos:
                validas.add(n)
                if n not in vistos:            # dedup dentro del marcador, conservando orden
                    vistos.add(n)
                    vals.append(n)
            else:
                invalidas.add(n)
        if not vals:
            return MARCA_INVALIDA              # todos invalidos: se neutraliza el marcador entero
        if len(vals) == len(nums):
            return m.group(0)                  # todos validos: se conserva EXACTAMENTE igual
        return "[" + ", ".join(str(n) for n in vals) + "]"   # mixto: se quitan los invalidos

    limpia = _RE_MARCADOR.sub(_sustituir, texto)
    return {
        "respuesta_limpia": limpia,
        "citas_validas": sorted(validas),
        "citas_invalidas": sorted(invalidas),
        "ok": not invalidas,
    }
