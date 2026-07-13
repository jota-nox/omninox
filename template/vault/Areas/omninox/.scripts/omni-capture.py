#!/usr/bin/env python3
"""
OmniNox — captura garantida de sessões do Claude Code.

Princípio: o verbatim NÃO depende do modelo lembrar de salvar.
O Claude Code já grava todo transcript em ~/.claude/projects/**/*.jsonl;
este script minera esses arquivos para a camada raw/ do vault.

Modos:
  (hook)      stdin recebe o JSON do hook (Stop/PreCompact/SessionEnd/SessionStart)
  --backfill  varre ~/.claude/projects/ e extrai tudo que ainda não foi extraído
  --extract F extrai um .jsonl específico

Garantias:
  - exit 0 SEMPRE em modo hook (falha de memória nunca pode quebrar a sessão)
  - escrita atômica (temp + os.replace)
  - só escreve no vault canônico (marker .omninox-vault), nunca em cópias
  - git commit do vault a cada captura; mirror rsync no SessionEnd
"""
import json, os, re, subprocess, sys, tempfile
from datetime import datetime, timedelta, timezone

CONFIG_FILE = os.path.expanduser("~/.config/omninox/config.json")
DEFAULT_VAULT = os.path.expanduser("~/Documents/omninox")

def _load_vault():
    try:
        with open(CONFIG_FILE) as f:
            v = json.load(f).get("vaultPath")
            if v:
                return os.path.expanduser(v)
    except Exception:
        pass
    return DEFAULT_VAULT

VAULT = _load_vault()
MARKER = os.path.join(VAULT, ".omninox-vault")
RAW = os.path.join(VAULT, "Areas", "omninox", "raw")
LEDGER = os.path.join(RAW, "ledger.tsv")
ERRLOG = os.path.join(RAW, ".capture-errors.log")
PROJECTS = os.path.expanduser("~/.claude/projects")
MIRROR = os.path.expanduser("~/.claude/omninox-backup/vault-mirror")
MIN_BYTES = 50_000          # sessões menores ficam só no ledger (triviais)

def log_err(msg):
    try:
        os.makedirs(RAW, exist_ok=True)
        with open(ERRLOG, "a") as f:
            f.write(f"{datetime.now().isoformat()} {msg}\n")
    except Exception:
        pass

def local_ts(iso):
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone()
        return dt.strftime("%Y-%m-%d %H:%M")
    except Exception:
        return iso or "?"

def blocks_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content
                         if isinstance(b, dict) and b.get("type") == "text")
    return ""

def clean_user_text(txt):
    txt = re.sub(r"<system-reminder>.*?</system-reminder>", "", txt, flags=re.S)
    txt = re.sub(r"<local-command-caveat>.*?</local-command-caveat>", "", txt, flags=re.S)
    txt = txt.strip()
    m = re.search(r"<command-name>(.*?)</command-name>", txt, re.S)
    if m:
        args = re.search(r"<command-args>(.*?)</command-args>", txt, re.S)
        return f"[comando: {m.group(1).strip()} {(args.group(1).strip() if args else '')}]".strip()
    return txt

def extract_jsonl(path):
    """Retorna (front, body, meta) do transcript, ou None se vazio de conteúdo."""
    first_ts = last_ts = None
    cwd = ""
    n_user = n_asst = 0
    files_touched = set()
    out = []
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError as e:
        log_err(f"extract open fail {path}: {e}")
        return None
    with fh:
        for line in fh:
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("isMeta"):
                continue
            ts = d.get("timestamp")
            if ts:
                first_ts = first_ts or ts
                last_ts = ts
            cwd = d.get("cwd") or cwd
            t = d.get("type")
            msg = d.get("message") or {}
            if t == "user":
                content = msg.get("content")
                if isinstance(content, list) and any(
                        isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
                    continue
                txt = clean_user_text(blocks_text(content).strip())
                if not txt:
                    continue
                if txt.startswith("[comando:"):
                    out.append(f"**USUÁRIO** ({local_ts(ts)}): {txt}\n")
                    continue
                n_user += 1
                out.append(f"## USUÁRIO ({local_ts(ts)})\n\n{txt}\n")
            elif t == "assistant":
                content = msg.get("content")
                if isinstance(content, list):
                    for b in content:
                        if isinstance(b, dict) and b.get("type") == "tool_use" \
                                and b.get("name") in ("Write", "Edit", "NotebookEdit"):
                            fp = (b.get("input") or {}).get("file_path")
                            if fp:
                                files_touched.add(fp)
                txt = blocks_text(content).strip()
                if not txt:
                    continue
                n_asst += 1
                out.append(f"### CLAUDE ({local_ts(ts)})\n\n{txt}\n")
    if n_user + n_asst == 0:
        return None
    sid = os.path.basename(path).replace(".jsonl", "")
    date = local_ts(first_ts)[:10] if first_ts else "0000-00-00"
    front = "\n".join([
        "---",
        f"session_id: {sid}",
        f"cwd: {cwd}",
        f"started: {local_ts(first_ts)}",
        f"ended: {local_ts(last_ts)}",
        f"msgs_usuario: {n_user}",
        f"blocos_claude: {n_asst}",
        "camada: raw  # verbatim minerado do transcript — imutável, nunca editar",
        "files_touched:",
    ] + [f"  - {f}" for f in sorted(files_touched)[:40]] + ["---", ""])
    return front, "\n".join(out), {"sid": sid, "date": date, "cwd": cwd}

def atomic_write(path, content):
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        f.write(content)
    os.replace(tmp, path)
    return os.path.getsize(path)

def raw_path_for(meta):
    slug = re.sub(r"[^A-Za-z0-9_-]", "", os.path.basename(meta["cwd"] or "x"))[:24] or "x"
    return os.path.join(RAW, f"{meta['date']}_{meta['sid'][:8]}_{slug}.md")

def check_vault():
    if not os.path.isfile(MARKER):
        log_err(f"ABORT: marker {MARKER} ausente — vault não-canônico ou movido")
        return False
    return True

def update_ledger(sid, cwd, tpath, event, extracted=""):
    rows = {}
    if os.path.isfile(LEDGER):
        with open(LEDGER) as f:
            for ln in f:
                p = ln.rstrip("\n").split("\t")
                if len(p) >= 6:
                    rows[p[0]] = p
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    old = rows.get(sid, [sid, now, "", "", "", ""])
    rows[sid] = [sid, old[1] or now, now, cwd or old[3], tpath or old[4],
                 extracted or old[5]]
    body = "session_id\tfirst_seen\tlast_seen\tcwd\ttranscript\textracted_to\n" + \
           "\n".join("\t".join(r) for r in rows.values()) + "\n"
    atomic_write(LEDGER, body)

def git_commit(msg):
    try:
        subprocess.run(["git", "-C", VAULT, "add", "-A"], capture_output=True, timeout=20)
        r = subprocess.run(["git", "-C", VAULT, "diff", "--cached", "--quiet"],
                           capture_output=True, timeout=20)
        if r.returncode != 0:
            subprocess.run(["git", "-C", VAULT, "commit", "-q", "-m", msg],
                           capture_output=True, timeout=30)
    except Exception as e:
        log_err(f"git fail: {e}")

def mirror():
    try:
        os.makedirs(MIRROR, exist_ok=True)
        subprocess.run(["rsync", "-a", "--delete", VAULT + "/", MIRROR + "/"],
                       capture_output=True, timeout=120)
    except Exception as e:
        log_err(f"mirror fail: {e}")

def notify(title, msg):
    try:
        subprocess.run(["osascript", "-e",
                        f'display notification "{msg}" with title "{title}"'],
                       capture_output=True, timeout=10)
    except Exception:
        pass

def has_remote():
    try:
        r = subprocess.run(["git", "-C", VAULT, "remote"], capture_output=True, timeout=10)
        return b"origin" in r.stdout
    except Exception:
        return False

def pull_rebase():
    # sync multi-máquina: integra o remoto antes de trabalhar/pushar.
    # Halls e ledger fazem merge automático (merge=union no .gitattributes);
    # conflito real ABORTA e alerta — nunca resolver em silêncio (regra 8).
    if not has_remote():
        return
    try:
        r = subprocess.run(["git", "-C", VAULT, "pull", "--rebase", "--autostash",
                            "-q", "origin", "master"], capture_output=True, timeout=90)
        if r.returncode != 0:
            subprocess.run(["git", "-C", VAULT, "rebase", "--abort"],
                           capture_output=True, timeout=30)
            err = r.stderr.decode()[:300]
            log_err(f"pull-rebase conflito/falha: {err}")
            if "CONFLICT" in err or "conflict" in err:
                notify("OmniNox", "Conflito de sync no vault — resolver manualmente")
    except Exception as e:
        log_err(f"pull fail: {e}")

def push_backup():
    # backup remoto opcional (sem origin = usuário escolheu ficar local).
    # Best-effort: falha vira log, nunca quebra a sessão.
    if not has_remote():
        return
    try:
        r = subprocess.run(["git", "-C", VAULT, "push", "-q", "origin", "master"],
                           capture_output=True, timeout=60)
        if r.returncode != 0:
            log_err(f"push fail: {r.stderr.decode()[:200]}")
    except Exception as e:
        log_err(f"push fail: {e}")

def capture(tpath, sid, cwd, event):
    if not check_vault():
        return
    extracted = ""
    try:
        if tpath and os.path.isfile(tpath) and os.path.getsize(tpath) >= MIN_BYTES:
            res = extract_jsonl(tpath)
            if res:
                front, body, meta = res
                dest = raw_path_for(meta)
                atomic_write(dest, front + body)
                extracted = os.path.relpath(dest, RAW)
    except Exception as e:
        log_err(f"capture extract fail {tpath}: {e}")
    try:
        update_ledger(sid or "?", cwd or "", tpath or "", event, extracted)
    except Exception as e:
        log_err(f"ledger fail: {e}")
    git_commit(f"omni-capture: {event} {sid[:8] if sid else '?'}" +
               (f" -> {extracted}" if extracted else ""))
    if event == "SessionEnd":
        mirror()
        pull_rebase()
        push_backup()

def hook_mode():
    try:
        data = json.load(sys.stdin)
    except Exception as e:
        log_err(f"stdin parse fail: {e}")
        return
    capture(data.get("transcript_path"), data.get("session_id"),
            data.get("cwd"), data.get("hook_event_name", "?"))

def backfill():
    if not check_vault():
        sys.exit(1)
    done = skipped = 0
    for root, dirs, files in os.walk(PROJECTS):
        # só sessões principais: filhos diretos de ~/.claude/projects/<projeto>/
        # (subdirs contêm transcripts de subagentes — ruído, não pensamento)
        if os.path.dirname(root) != PROJECTS.rstrip("/") and root != PROJECTS:
            dirs[:] = []
            continue
        if root == PROJECTS:
            continue
        for f in sorted(files):
            if not f.endswith(".jsonl") or f.startswith("agent-"):
                continue
            p = os.path.join(root, f)
            if os.path.getsize(p) < MIN_BYTES:
                skipped += 1
                continue
            res = extract_jsonl(p)
            if not res:
                skipped += 1
                continue
            front, body, meta = res
            dest = raw_path_for(meta)
            if os.path.isfile(dest):
                skipped += 1
                continue
            size = atomic_write(dest, front + body)
            update_ledger(meta["sid"], meta["cwd"], p, "backfill",
                          os.path.relpath(dest, RAW))
            print(f"OK {size:>9,}B  {os.path.basename(dest)}")
            done += 1
    print(f"\nbackfill: {done} extraídos, {skipped} pulados (triviais/já extraídos)")
    git_commit(f"omni-capture: backfill de {done} sessões")

if __name__ == "__main__":
    if "--backfill" in sys.argv:
        backfill()
    elif "--extract" in sys.argv:
        p = sys.argv[sys.argv.index("--extract") + 1]
        res = extract_jsonl(p)
        if res:
            front, body, meta = res
            dest = raw_path_for(meta)
            print(f"{atomic_write(dest, front + body):,}B -> {dest}")
    else:
        hook_mode()
        sys.exit(0)
