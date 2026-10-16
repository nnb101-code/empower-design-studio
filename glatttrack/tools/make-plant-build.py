#!/usr/bin/env python3
"""GlattTrack: make the PLANT build of the app from the regular (test) file.

    python3 tools/make-plant-build.py kosher-app-v10.32.html      ->  kosher-app-v10.32-plant.html

The plant build has no cloud address in it at all (no test-server URL, no test-server key, no
public CDN for the database library): it works only with the plant server's gt-config.js and
vendor/supabase.js. Opened anywhere else it stops with "call the installer". The script refuses
to write the file if any cloud address is left in it.
"""
import re, sys
src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) > 2 else re.sub(r'\.html$', '-plant.html', src)
s = open(src, encoding='utf-8').read()
mark = "window.GT_BUILD = 'test';   /* GT_BUILD_MARK */"
if mark not in s:
    sys.exit('the build mark is missing — is this a GlattTrack app file v10.32 or later?')
s = s.replace(mark, "window.GT_BUILD = 'plant';   /* GT_BUILD_MARK */")
# the cloud test server: its address and its public key
s = re.sub(r"'https://[a-z0-9]+\.supabase\.co'", "''", s)
s = re.sub(r"'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+'", "''", s)
# the public CDN for the reading (OCR) library: only vendor/tesseract/ on the plant server
s = s.replace("const GT_OCR_CDN='https://cdn.jsdelivr.net/npm/';", "const GT_OCR_CDN='';")
# the public CDN for the database library (the plant server serves vendor/supabase.js)
s = s.replace("'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js'", "'vendor/supabase.js'")
left = [m for m in re.findall(r'https://[A-Za-z0-9.\-]+', s) if re.search(r'supabase\.co$|jsdelivr', m) and 'xxxx' not in m]
if left:
    sys.exit('cloud addresses still in the file: ' + ', '.join(sorted(set(left))))
open(dst, 'w', encoding='utf-8').write(s)
print('written', dst)
