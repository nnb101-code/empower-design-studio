#!/usr/bin/env python3
# GlattTrack — Wi-Fi scanners through the plant server (v10.38, owner). Runs all the time (gt-scanner-relay.service),
# started by scanner-relay.sh. A Wi-Fi scanner is set to "TCP client" → this server, port 9300 (GT_SCANNER_PORT).
# Each code it sends (a line ending with Enter) is kept with the scanner's address (scanner_scans): the team leader's
# "search" shows it, and the station the scanner is given to receives it. Only addresses of the plant network;
# only printable codes up to 200 characters. On the standby server (read-only) nothing is written.
import os, socket, subprocess, threading, time, ipaddress

PSQL = [os.environ.get('GT_PSQL', 'psql'), '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1',
        '-h', os.environ.get('GT_PGHOST', '/var/run/postgresql'), '-p', os.environ.get('GT_PG_PORT', '5432'),
        '-U', os.environ.get('GT_PGUSER', 'postgres'), '-d', os.environ.get('GT_DB', 'postgres')]
PORT = int(os.environ.get('GT_SCANNER_PORT', '9300'))
TEST_LOCAL = os.environ.get('GT_SCANNER_TEST_LOCAL') == '1'      # tests only: a scanner on this machine

def sql(stmt, **v):
    args = PSQL[:]
    for k, x in v.items(): args += ['-v', '%s=%s' % (k, x)]
    try:
        return subprocess.run(args, input=stmt, capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:
        return ''

def allowed(ip):
    try:
        a = ipaddress.ip_address(ip)
        return a.is_private and (TEST_LOCAL or not a.is_loopback)
    except ValueError:
        return False

def save(ip, code):
    code = ''.join(ch for ch in code if ch.isprintable())[:200].strip()
    if not code: return
    sql("""insert into scanner_scans (ip, code) select :'ip', :'code' where not pg_is_in_recovery();
           delete from scanner_scans where at < now() - interval '1 day' and not pg_is_in_recovery();""", ip=ip, code=code)

def client(conn, ip):
    buf = b''
    conn.settimeout(3600)
    try:
        while True:
            data = conn.recv(1024)
            if not data: break
            buf += data
            while True:
                cut = min([i for i in (buf.find(b'\r'), buf.find(b'\n')) if i >= 0], default=-1)
                if cut < 0: break
                line, buf = buf[:cut], buf[cut + 1:]
                if line: save(ip, line.decode('utf-8', 'replace'))
            if len(buf) > 1000: buf = b''
    except Exception:
        pass
    finally:
        if buf.strip(): save(ip, buf.decode('utf-8', 'replace'))   # a scanner that sends no Enter at the end
        conn.close()

def beat():
    while True:
        sql("""insert into plant_state (key, value) select 'scannerRelayAt', now()::text where not pg_is_in_recovery()
               on conflict (key) do update set value = excluded.value, updated_at = now();""")
        time.sleep(30)

threading.Thread(target=beat, daemon=True).start()
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((os.environ.get('GT_SCANNER_BIND', '0.0.0.0'), PORT)); srv.listen(32)
while True:
    c, (ip, _) = srv.accept()
    if not allowed(ip): c.close(); continue
    threading.Thread(target=client, args=(c, ip), daemon=True).start()
