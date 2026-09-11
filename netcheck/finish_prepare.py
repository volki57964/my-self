#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import sys
root=Path(sys.argv[1]); java=root/'app/src/main/java/com/emanuelef/remote_capture'
p=java/'PCAPdroid.java';s=p.read_text().replace('// NetCheck: avoid persistent native diagnostic logs outside explicit reports.','if(!isUnderTest())\n            Log.init(getCacheDir().getAbsolutePath());');p.write_text(s)
p=java/'Log.java';s=p.read_text().replace('cachedir + "/" + DEFAULT_LOGGER_PATH','"/dev/null"').replace('cachedir + "/" + MITM_LOGGER_PATH','"/dev/null"');p.write_text(s)
# Treat partially written interrupted runs as interrupted when the user opens the app again.
p=java/'netcheck/NetCheckActivity.java';s=p.read_text();s=s.replace('super.onCreate(b);getWindow()', '''super.onCreate(b);
        if(NetRunService.instance==null) {
            for(File d:NetReport.reports(this)) try {
                File f=new File(d,"report.json"); JSONObject r=new JSONObject(Files.readString(f.toPath()));
                if("running".equals(r.optString("status"))) {
                    r.put("status","interrupted_process");
                    NetReport.atomic(f,r.toString(2));
                    NetReport.atomic(new File(d,"summary.txt"),NetReport.summary(r));
                }
            } catch(Exception ignored) {}
        }
        getWindow()''');p.write_text(s)
print('Disabled persistent upstream engine logs and added interrupted-run recovery.')
