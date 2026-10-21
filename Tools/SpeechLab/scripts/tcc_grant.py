#!/usr/bin/env python3
"""Insert 'allowed' TCC rows for a service into the user and system TCC databases.

usage: tcc_grant.py SERVICE CLIENT [CLIENT...]   (a CLIENT starting with '/' is a path, otherwise a bundle id)
Works on GitHub macOS runners (SIP disabled); prints what succeeded so the probe can learn what is writable.
"""
import os, sqlite3, sys, time

service, clients = sys.argv[1], sys.argv[2:]
dbs = [os.path.expanduser("~/Library/Application Support/com.apple.TCC/TCC.db"),
       "/Library/Application Support/com.apple.TCC/TCC.db"]
now = int(time.time())
for db in dbs:
    try:
        con = sqlite3.connect(db)
        cols = [r[1] for r in con.execute("PRAGMA table_info(access)")]
        for c in clients:
            vals = {"service": service, "client": c, "client_type": 1 if c.startswith("/") else 0,
                    "auth_value": 2, "auth_reason": 4, "auth_version": 1, "csreq": None, "policy_id": None,
                    "indirect_object_identifier_type": 0, "indirect_object_identifier": "UNUSED",
                    "indirect_object_code_identity": None, "flags": 0, "last_modified": now, "pid": None,
                    "pid_version": None, "boot_uuid": "UNUSED", "last_reminded": now}
            row = [vals.get(k) for k in cols]
            con.execute(f"INSERT OR REPLACE INTO access ({','.join(cols)}) VALUES ({','.join('?' * len(cols))})", row)
        con.commit()
        n = con.execute("SELECT count(*) FROM access WHERE service=?", (service,)).fetchone()[0]
        print(f"OK {db}: {service} rows now {n}")
    except Exception as e:
        print(f"FAIL {db}: {e}")
