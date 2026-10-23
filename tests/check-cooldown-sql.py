"""Verify that the exact SQL used by manual refresh skips unexpired backoff."""
from pathlib import Path
import sqlite3
import re

source=(Path(__file__).resolve().parents[1]/'package/contents/ui/UploadStore.qml').read_text()
pattern=r'function setDueNowEligible\(now\)\s*\{[\s\S]*?tx\.executeSql\("([^"]+)"\s*,\s*\[now\]\);'
match=re.search(pattern,source)
assert match, 'Missing parameterized cooldown-aware update'
query=match.group(1)
assert 'failures=0 OR next_check_ms<=?' in query
conn=sqlite3.connect(':memory:')
conn.execute('CREATE TABLE channels(id TEXT PRIMARY KEY, failures INTEGER, next_check_ms INTEGER)')
now=10000000
for row in [('healthy',0,now+100000),('cooled',2,now+100000),('expired',2,now-100000)]:
    conn.execute('INSERT INTO channels VALUES(?,?,?)',row)
conn.execute(query,[now])
results=dict(conn.execute('SELECT id,next_check_ms FROM channels'))
assert results=={'healthy':0,'cooled':now+100000,'expired':0},results
print('PASS manual refresh SQL accelerates healthy/expired channels, preserves active cooldown')
