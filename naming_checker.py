#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
naming_checker.py — Gerador + verificador de disponibilidade de nomes de marca.

FERRAMENTA ISOLADA. Não importa nem lê nenhum outro arquivo do projeto.
Gera candidatos a nome (moldes fonéticos), filtra palavrão/conotação negativa/
clichê de saúde/nomes já mortos/infantilismo, e verifica via RDAP se o
domínio .com E o .com.br estão livres AO MESMO TEMPO. Só quem passa nos dois
vai para o CSV de saída.

COMO RODAR (passo a passo, sem precisar saber programar)
----------------------------------------------------------------------------
1. Abra o PowerShell nesta pasta (a mesma onde está este arquivo).
2. Se ainda não tiver a biblioteca "httpx" instalada, rode uma vez:
       py -m pip install httpx
3. Primeiro rode em MODO TESTE (só ~200 candidatos, rápido, para conferir
   que tudo funciona antes de gastar horas checando milhares):
       py naming_checker.py --test
4. Confira as primeiras linhas de "nomes_disponiveis.csv" e o arquivo
   "log_execucao.txt". Se estiver tudo certo, rode a versão completa:
       py naming_checker.py
5. O processo é LENTO de propósito (para não sobrecarregar os servidores de
   domínio) e pode demorar bastante (pode ser horas, dependendo do volume).
   Pode fechar e rodar de novo a qualquer momento: ele usa um arquivo de
   cache ("rdap_cache.json") e RETOMA de onde parou, sem perder trabalho
   nem duplicar linhas no CSV.

ARQUIVOS GERADOS (na mesma pasta deste script)
  - nomes_disponiveis.csv  -> só os candidatos APROVADOS (.com e .com.br livres)
  - log_execucao.txt       -> resumo de cada execução (totais e tempo)
  - rdap_cache.json        -> cache técnico, não precisa mexer

IMPORTANTE: mesmo os nomes aprovados aqui ainda precisam ser conferidos
manualmente no INPI (colisão por semelhança fonética, que este script não
consegue avaliar) e nas redes sociais (Instagram/TikTok/LinkedIn bloqueiam
checagem automática). O CSV já marca isso nas colunas
"inpi_conferir_manual" e "handle_conferir_manual".
"""

import argparse
import asyncio
import csv
import json
import random
import re
import sys
import time
from datetime import datetime
from pathlib import Path

try:
    import httpx
except ImportError:
    print("ERRO: a biblioteca 'httpx' não está instalada.")
    print("Rode primeiro:  py -m pip install httpx")
    sys.exit(1)

# ---------------------------------------------------------------------------
# 1) BLOCOS FONÉTICOS E MOLDES DE GERAÇÃO
# ---------------------------------------------------------------------------

VOGAIS = "aeiou"
CONSOANTES = "bcdfgjklmnprstvz"
CLUSTERS = ["br", "tr", "pr", "gr", "fr", "vr", "bl", "cl", "fl", "pl"]
ONSETS = list(CONSOANTES) + CLUSTERS  # início de sílaba: consoante simples ou cluster

PREFIXOS_ARVORE = ["seiv", "ram", "brot", "cerne", "arbo", "xilem", "rai",
                    "tron", "folha", "semen"]
SUFIXOS_ARVORE = ["a", "o", "e", "ia", "ly", "on", "ora"]


def mold_cvcv():
    for o1 in ONSETS:
        for v1 in VOGAIS:
            for o2 in ONSETS:
                for v2 in VOGAIS:
                    yield o1 + v1 + o2 + v2, "CVCV_principal"


def mold_vcv():
    for v1 in VOGAIS:
        for o in ONSETS:
            for v2 in VOGAIS:
                yield v1 + o + v2, "VCV_principal"


def mold_vcvc():
    for v1 in VOGAIS:
        for o in ONSETS:
            for v2 in VOGAIS:
                for c in CONSOANTES:
                    yield v1 + o + v2 + c, "VCVC_principal"


def mold_cvc():
    for o in ONSETS:
        for v in VOGAIS:
            for c in CONSOANTES:
                yield o + v + c, "CVC_medio"


def mold_cvvc():
    for o in ONSETS:
        for v1 in VOGAIS:
            for v2 in VOGAIS:
                for c in CONSOANTES:
                    yield o + v1 + v2 + c, "CVVC_medio"


def mold_vccv():
    # o par de consoantes no meio é sempre um cluster válido de início de
    # sílaba (nunca uma dupla consoante arbitrária)
    for v1 in VOGAIS:
        for cl in CLUSTERS:
            for v2 in VOGAIS:
                yield v1 + cl + v2, "VCCV_medio"


def mold_cvvcvc():
    for o in ONSETS:
        for v1 in VOGAIS:
            for v2 in VOGAIS:
                for cmid in CONSOANTES:
                    for v3 in VOGAIS:
                        for cfim in CONSOANTES:
                            yield o + v1 + v2 + cmid + v3 + cfim, "CVVCVC_medio"


def mold_cvvcv_ly():
    # estilo "Geely": CVVCV + sufixo -ly
    for o in ONSETS:
        for v1 in VOGAIS:
            for v2 in VOGAIS:
                for cmid in CONSOANTES:
                    for v3 in VOGAIS:
                        yield o + v1 + v2 + cmid + v3 + "ly", "CVVCV_ly"


def mold_lll():
    # 3 letras, só consoante simples (sem cluster, não cabe em 3 letras)
    for o in CONSOANTES:
        for v in VOGAIS:
            for c in CONSOANTES:
                yield o + v + c, "LLL_menor"


def mold_arvore():
    for p in PREFIXOS_ARVORE:
        for s in SUFIXOS_ARVORE:
            yield p + s, "RAIZ_ARVORE_menor"


def mold_vcvcv():
    # estilo "Omada": V C V C V (5 letras na base; até 7 se algum C virar cluster)
    for v1 in VOGAIS:
        for c1 in ONSETS:
            for v2 in VOGAIS:
                for c2 in ONSETS:
                    for v3 in VOGAIS:
                        yield v1 + c1 + v2 + c2 + v3, "VCVCV_omada"


def gerar_todos():
    yield from mold_cvcv()
    yield from mold_vcv()
    yield from mold_vcvc()
    yield from mold_cvc()
    yield from mold_cvvc()
    yield from mold_vccv()
    yield from mold_cvvcvc()
    yield from mold_cvvcv_ly()
    yield from mold_lll()
    yield from mold_arvore()
    yield from mold_vcvcv()

# Nota sobre VCVCV_omada + --length: como C1/C2 podem ser consoante simples (1 letra)
# ou cluster (2 letras), o comprimento final da palavra já denuncia a variante:
#   5 letras = C1 e C2 ambos simples (a variante "fiel" ao Omada real, sem cluster)
#   6 letras = um dos dois é cluster
#   7 letras = os dois são cluster
# Por isso não existe um molde "_simples" separado: filtrar VCVCV_omada com --length 5
# já isola exatamente essa variante (evita duplicar candidatos que o dedup descartaria).


# ---------------------------------------------------------------------------
# 2) VALIDAÇÃO DE PRONUNCIABILIDADE (camada de segurança extra)
# ---------------------------------------------------------------------------

_VOGAL_EXT = set(VOGAIS) | {"y"}  # "y" também soa como vogal no final (-ly)


def _grupos_consoantes(palavra):
    """Retorna lista de (grupo_de_consoantes, termina_a_palavra). `termina_a_palavra`
    só é True pro grupo que é literalmente o final da string (sem vogal depois) —
    não pro último grupo da lista, que pode muito bem ter uma vogal final depois dele."""
    grupos = []
    atual = ""
    for ch in palavra:
        if ch in _VOGAL_EXT:
            if atual:
                grupos.append((atual, False))
                atual = ""
        else:
            atual += ch
    if atual:
        grupos.append((atual, True))
    return grupos


def valida_pronunciabilidade(palavra):
    grupos = _grupos_consoantes(palavra)
    if not grupos:
        return False
    for grupo, termina_palavra in grupos:
        if len(grupo) >= 3:
            return False
        if len(grupo) == 2:
            if termina_palavra:
                return False  # cluster nunca no final da palavra
            if grupo not in CLUSTERS:
                return False  # dupla consoante fora da lista permitida
    return True


def contar_silabas(palavra):
    return len(re.findall(r"[aeiouy]+", palavra))


ALERTA_GRAFEMAS = ["j", "ll", "ñ", "x", "qu"]


def tem_alerta_pronuncia(palavra):
    if palavra.startswith("h"):
        return True
    return any(g in palavra for g in ALERTA_GRAFEMAS)


# ---------------------------------------------------------------------------
# 3) FILTROS DE CONTEÚDO (blocos A-G, por posição)
# ---------------------------------------------------------------------------

BLOCO_A = [  # contém em qualquer posição — vulgar/ofensivo
    "caga", "cago", "merd", "bost", "puta", "puto", "viad", "buce", "boce",
    "xota", "porra", "caralh", "foder", "fode", "bunda", "peid", "traira",
    "piru",
    "fuck", "fuk", "shit", "sht", "cunt", "dick", "cock", "pussy", "puss",
    "slut", "whor", "bitch", "crap", "turd", "douch", "jizz", "wank",
    "bollock", "arse", "tit",
    "caca", "cago", "culo", "mierd", "puta", "puto", "cono", "coño",
    "verga", "pinch", "joder", "cabron", "pendej", "carajo", "polla",
    "zorra", "maric", "chinga", "chingo", "pedo", "moco",
]

BLOCO_B = [  # termina com
    "cu", "ku", "kk", "coco", "caca", "popo", "bebe", "nha", "nho",
    "ass", "ho", "hoe", "fu", "poo", "pee", "jr",
    "culo", "caca", "pis", "caco", "ono",
]

BLOCO_C = [  # começa com
    "xi", "caca", "caga",
    "ass",
    "caca", "culo",
]

BLOCO_D = [  # conotação negativa (3 idiomas)
    "mort", "muert", "dor", "dolor", "chor", "fim", "mal", "feio", "feo",
    "frac", "debil", "lixo", "sujo", "medo", "miedo", "pena", "dead", "die",
    "kill", "pain", "sick", "ill", "sad", "fail", "dumb", "ugly", "poor",
    "sin", "evil", "war", "pobre", "triste", "enferm", "pecad",
]

BLOCO_E_CONTEM = [  # cheiro de B2B/clínico/saturado — contém em qualquer posição
    "med", "clin", "diag", "farm", "longev", "vita", "vida", "sano", "cura",
    "dr",
]
BLOCO_E_SUFIXO = ["tech", "lab", "corp", "soft", "sys", "ex"]  # só como terminação

BLOCO_F = [  # nomes já mortos por colisão
    "viora", "longeva", "longevo", "longevia", "vitalonga", "perena",
    "perene", "anelo",
]

BLOCO_G = [  # infantil (sílaba dobrada de fralda)
    "caca", "popo", "bebe", "tata", "mimi", "dodo", "nene",
]


def _levenshtein(a, b):
    if a == b:
        return 0
    if abs(len(a) - len(b)) > 2:
        return 99
    la, lb = len(a), len(b)
    dp = list(range(lb + 1))
    for i in range(1, la + 1):
        novo = [i] + [0] * lb
        for j in range(1, lb + 1):
            custo = 0 if a[i - 1] == b[j - 1] else 1
            novo[j] = min(dp[j] + 1, novo[j - 1] + 1, dp[j - 1] + custo)
        dp = novo
    return dp[lb]


def _parecido_com_morto(palavra):
    for alvo in BLOCO_F:
        if abs(len(palavra) - len(alvo)) > 1:
            continue
        if _levenshtein(palavra, alvo) <= 1:
            return True
    return False


def motivo_rejeicao(p):
    if any(s in p for s in BLOCO_A):
        return "bloco_a_ofensivo"
    if any(p.endswith(s) for s in BLOCO_B):
        return "bloco_b_termina"
    if any(p.startswith(s) for s in BLOCO_C):
        return "bloco_c_comeca"
    if any(s in p for s in BLOCO_D):
        return "bloco_d_negativo"
    if any(s in p for s in BLOCO_E_CONTEM):
        return "bloco_e_clinico"
    if any(p.endswith(s) for s in BLOCO_E_SUFIXO):
        return "bloco_e_saturado"
    if p in BLOCO_F or _parecido_com_morto(p):
        return "bloco_f_morto"
    if any(s in p for s in BLOCO_G):
        return "bloco_g_infantil"
    return None


# ---------------------------------------------------------------------------
# 4) PIPELINE DE GERAÇÃO + FILTRO + DEDUP
# ---------------------------------------------------------------------------

def gerar_candidatos_filtrados(contadores):
    vistos = {}
    total_gerados = 0
    for palavra, molde in gerar_todos():
        total_gerados += 1
        limite_ok = (len(palavra) == 3) if molde == "LLL_menor" else (4 <= len(palavra) <= 7)
        if not limite_ok:
            continue
        if not valida_pronunciabilidade(palavra):
            continue
        if motivo_rejeicao(palavra) is not None:
            continue
        if palavra in vistos:
            continue
        vistos[palavra] = (molde, tem_alerta_pronuncia(palavra))
    contadores["total_gerados"] = total_gerados
    contadores["total_apos_filtros"] = len(vistos)
    return [(nome, dados[0], dados[1]) for nome, dados in vistos.items()]


# ---------------------------------------------------------------------------
# 5) VERIFICAÇÃO RDAP (assíncrona, com cache em disco e backoff)
# ---------------------------------------------------------------------------

def carregar_json(caminho, padrao):
    if caminho.exists():
        try:
            with open(caminho, "r", encoding="utf-8") as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            return padrao
    return padrao


def salvar_cache(caminho, cache):
    tmp = caminho.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(cache, f)
    tmp.replace(caminho)


def carregar_nomes_ja_escritos(csv_path):
    nomes = set()
    if csv_path.exists():
        with open(csv_path, "r", newline="", encoding="utf-8") as f:
            leitor = csv.DictReader(f)
            for linha in leitor:
                if linha.get("nome"):
                    nomes.add(linha["nome"])
    return nomes


async def _fetch_com_retry(client, url, tentativas=4):
    espera = 1.0
    for tentativa in range(tentativas):
        try:
            resp = await client.get(url)
        except (httpx.TimeoutException, httpx.TransportError, httpx.HTTPError):
            if tentativa == tentativas - 1:
                return "ERRO_CHECAR"
            await asyncio.sleep(espera)
            espera *= 2
            continue
        if resp.status_code == 404:
            return "LIVRE"
        if resp.status_code == 200:
            return "REGISTRADO"
        # 429 (rate limit) ou qualquer outro código inesperado: recua e tenta de novo
        if tentativa == tentativas - 1:
            return "ERRO_CHECAR"
        await asyncio.sleep(espera)
        espera *= 2
    return "ERRO_CHECAR"


async def checar_dominio(client, sem, dominio, url, cache):
    if dominio in cache:
        return cache[dominio]
    async with sem:
        status = await _fetch_com_retry(client, url)
    cache[dominio] = status
    return status


async def processar_um(client, sem, cache, nome, molde, alerta):
    url_com = f"https://rdap.org/domain/{nome}.com"
    url_br = f"https://rdap.registro.br/domain/{nome}.com.br"
    com_status = await checar_dominio(client, sem, f"{nome}.com", url_com, cache)
    combr_status = await checar_dominio(client, sem, f"{nome}.com.br", url_br, cache)
    return nome, molde, contar_silabas(nome), com_status, combr_status, alerta


async def verificar_candidatos(candidatos, concorrencia, tamanho_lote, pausa,
                                cache_path, csv_path):
    cache = carregar_json(cache_path, {})
    ja_escritos = carregar_nomes_ja_escritos(csv_path)
    sem = asyncio.Semaphore(concorrencia)

    aprovados = 0
    erros = 0
    avaliados = 0

    modo_arquivo = "a" if csv_path.exists() else "w"
    with open(csv_path, modo_arquivo, newline="", encoding="utf-8") as f_csv:
        writer = csv.writer(f_csv)
        if modo_arquivo == "w":
            writer.writerow([
                "nome", "molde", "silabas", "com_status", "combr_status",
                "alerta_pronuncia", "data_checagem",
                "inpi_conferir_manual", "handle_conferir_manual",
            ])

        headers = {
            "User-Agent": "naming-checker/1.0 (uso pessoal - apoio a decisao de naming)",
            "Accept": "application/rdap+json",
        }
        async with httpx.AsyncClient(timeout=10.0, follow_redirects=True,
                                      headers=headers) as client:
            total_lotes = (len(candidatos) + tamanho_lote - 1) // max(tamanho_lote, 1)
            for i in range(0, len(candidatos), tamanho_lote):
                lote = [c for c in candidatos[i:i + tamanho_lote] if c[0] not in ja_escritos]
                if not lote:
                    continue
                tarefas = [processar_um(client, sem, cache, nome, molde, alerta)
                           for nome, molde, alerta in lote]
                resultados = await asyncio.gather(*tarefas)
                for nome, molde, silabas, com_st, combr_st, alerta in resultados:
                    avaliados += 1
                    if com_st == "ERRO_CHECAR" or combr_st == "ERRO_CHECAR":
                        erros += 1
                    if com_st == "LIVRE" and combr_st == "LIVRE":
                        writer.writerow([
                            nome, molde, silabas, com_st, combr_st,
                            "SIM" if alerta else "NAO",
                            datetime.now().isoformat(timespec="seconds"),
                            "SIM", "SIM",
                        ])
                        aprovados += 1
                f_csv.flush()
                salvar_cache(cache_path, cache)
                print(f"  lote {i // tamanho_lote + 1}/{total_lotes}: "
                      f"{len(lote)} nomes checados | aprovados até agora: {aprovados} "
                      f"| erros até agora: {erros}")
                await asyncio.sleep(pausa)

    salvar_cache(cache_path, cache)
    return aprovados, erros, avaliados


def alocar_por_peso(capacidades, pesos, total):
    """Distribui `total` entre os moldes proporcionalmente a `pesos`, respeitando a
    capacidade (tamanho do pool) de cada um e redistribuindo sobra/falta pra sempre
    bater o total exato (a menos que a capacidade combinada de todos seja menor)."""
    moldes = list(capacidades.keys())
    alocacao = {m: min(round(pesos[m] * total), capacidades[m]) for m in moldes}

    diff = total - sum(alocacao.values())
    ordem_peso_desc = sorted(moldes, key=lambda m: -pesos[m])
    while diff > 0:
        avancou = False
        for m in ordem_peso_desc:
            if alocacao[m] < capacidades[m]:
                alocacao[m] += 1
                diff -= 1
                avancou = True
                if diff == 0:
                    break
        if not avancou:
            break  # capacidade total esgotada, não dá pra bater o total pedido

    ordem_peso_asc = sorted(moldes, key=lambda m: pesos[m])
    while diff < 0:
        for m in ordem_peso_asc:
            if alocacao[m] > 0:
                alocacao[m] -= 1
                diff += 1
                if diff == 0:
                    break

    return alocacao


# ---------------------------------------------------------------------------
# 6) MAIN
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Gera e verifica disponibilidade real de nomes de marca (.com + .com.br)."
    )
    parser.add_argument("--test", action="store_true",
                         help="Modo teste: processa só ~200 candidatos (amostra aleatória).")
    parser.add_argument("--test-size", type=int, default=200,
                         help="Quantidade de candidatos no modo teste (padrão: 200).")
    parser.add_argument("--limit", type=int, default=None,
                         help="Limita a quantidade total de candidatos verificados na rede.")
    parser.add_argument("--concurrency", type=int, default=5,
                         help="Consultas RDAP simultâneas (padrão: 5).")
    parser.add_argument("--batch-size", type=int, default=25,
                         help="Quantos candidatos por lote antes de pausar (padrão: 25).")
    parser.add_argument("--pause", type=float, default=1.5,
                         help="Pausa em segundos entre lotes (padrão: 1.5).")
    parser.add_argument("--seed", type=int, default=42,
                         help="Semente aleatória para a amostra do modo teste (reprodutível).")
    parser.add_argument("--molde", type=str, default=None,
                         help="Filtra só candidatos de um molde específico, ou vários "
                              "separados por vírgula (ex.: CVCV_principal,VCV_principal,"
                              "VCVC_principal,RAIZ_ARVORE_menor).")
    parser.add_argument("--sample", type=int, default=None,
                         help="Em vez de pegar os N primeiros (ordem alfabética do "
                              "molde), sorteia N candidatos aleatórios do pool "
                              "(ou do --molde, se combinado). Ignora --limit.")
    parser.add_argument("--peso-aleatorio", action="store_true",
                         help="Com --molde de vários moldes + --sample: em vez de "
                              "amostrar do pool combinado (o que afogaria moldes "
                              "pequenos), sorteia um peso por molde e distribui o "
                              "total de --sample proporcionalmente a esses pesos.")
    parser.add_argument("--length", type=int, default=None,
                         help="Filtra só candidatos com exatamente N letras "
                              "(útil p.ex. p/ isolar a variante sem cluster de um molde).")
    args = parser.parse_args()

    pasta = Path(__file__).resolve().parent
    csv_path = pasta / "nomes_disponiveis.csv"
    log_path = pasta / "log_execucao.txt"
    cache_path = pasta / "rdap_cache.json"

    inicio = time.time()
    contadores = {}

    print("Gerando e filtrando candidatos (offline, sem rede)...")
    candidatos = gerar_candidatos_filtrados(contadores)
    print(f"  total bruto gerado: {contadores['total_gerados']:,}")
    print(f"  total após filtros + dedup: {contadores['total_apos_filtros']:,}")

    moldes_alvo = None
    if args.molde:
        moldes_alvo = [m.strip() for m in args.molde.split(",") if m.strip()]
        candidatos = [c for c in candidatos if c[1] in moldes_alvo]
        print(f"  filtrado para moldes={moldes_alvo}: {len(candidatos):,} candidatos")

    if args.length:
        candidatos = [c for c in candidatos if len(c[0]) == args.length]
        print(f"  filtrado para length={args.length}: {len(candidatos):,} candidatos")

    modo_desc = "COMPLETO"
    if args.test:
        modo_desc = f"TESTE ({args.test_size} candidatos)"
        random.seed(args.seed)
        candidatos = random.sample(candidatos, min(args.test_size, len(candidatos)))
    elif args.sample and args.peso_aleatorio and moldes_alvo and len(moldes_alvo) > 1:
        random.seed(args.seed)
        baldes = {m: [c for c in candidatos if c[1] == m] for m in moldes_alvo}
        capacidades = {m: len(baldes[m]) for m in moldes_alvo}
        pesos_brutos = {m: random.random() for m in moldes_alvo}
        soma_pesos = sum(pesos_brutos.values())
        pesos = {m: p / soma_pesos for m, p in pesos_brutos.items()}
        alocacao = alocar_por_peso(capacidades, pesos, args.sample)
        candidatos = []
        for m in moldes_alvo:
            candidatos += random.sample(baldes[m], min(alocacao[m], len(baldes[m])))
        random.shuffle(candidatos)
        pesos_fmt = ", ".join(f"{m}={pesos[m]:.0%}({alocacao[m]}/{capacidades[m]})"
                               for m in moldes_alvo)
        modo_desc = f"COMPLETO (amostra ponderada de {sum(alocacao.values())}: {pesos_fmt})"
    elif args.sample:
        random.seed(args.seed)
        candidatos = random.sample(candidatos, min(args.sample, len(candidatos)))
        modo_desc = f"COMPLETO (amostra aleatória de {args.sample}" + \
                     (f", molde={args.molde}" if args.molde else "") + ")"
    elif args.limit:
        candidatos = candidatos[:args.limit]
        modo_desc = f"COMPLETO (limitado a {args.limit})"

    print(f"Modo: {modo_desc}")
    print(f"Verificando disponibilidade via RDAP (concorrência={args.concurrency})...")

    aprovados, erros, avaliados = asyncio.run(
        verificar_candidatos(candidatos, args.concurrency, args.batch_size,
                              args.pause, cache_path, csv_path)
    )

    duracao = time.time() - inicio

    with open(log_path, "a", encoding="utf-8") as f:
        f.write("=== Relatório de execução — Verificador de Naming ===\n")
        f.write(f"Data/hora: {datetime.now().isoformat(timespec='seconds')}\n")
        f.write(f"Modo: {modo_desc}\n")
        f.write("--- Geração ---\n")
        f.write(f"Total bruto gerado (todos os moldes, antes de filtros): {contadores['total_gerados']}\n")
        f.write(f"Total após filtros de conteúdo + pronunciabilidade + dedup: {contadores['total_apos_filtros']}\n")
        f.write("--- Verificação de domínio ---\n")
        f.write(f"Candidatos avaliados nesta execução: {avaliados}\n")
        f.write(f"Aprovados (.com e .com.br livres): {aprovados}\n")
        f.write(f"Erros ao checar (ERRO_CHECAR em pelo menos um domínio): {erros}\n")
        f.write("--- Tempo ---\n")
        f.write(f"Duração desta execução: {duracao:.1f}s\n")
        f.write("\n")

    print(f"\nConcluído em {duracao:.1f}s.")
    print(f"Avaliados nesta execução: {avaliados} | Aprovados: {aprovados} | Erros: {erros}")
    print(f"Resultados em: {csv_path}")
    print(f"Log em: {log_path}")


if __name__ == "__main__":
    main()
