#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import sys
root=Path(sys.argv[1]); java=root/'app/src/main/java/com/emanuelef/remote_capture'
p=java/'PCAPdroid.java';s=p.read_text().replace('// NetCheck: avoid persistent native diagnostic logs outside explicit reports.','if(!isUnderTest())\n            Log.init(getCacheDir().getAbsolutePath());');p.write_text(s)
p=java/'Log.java';s=p.read_text().replace('cachedir + "/" + DEFAULT_LOGGER_PATH','"/dev/null"').replace('cachedir + "/" + MITM_LOGGER_PATH','"/dev/null"');p.write_text(s)
# Android java.nio.file.Files does not expose Java 11 readString on this SDK.
p=java/'netcheck/NetReport.java';s=p.read_text().replace('public static String error(Throwable t)', '''public static String readText(java.nio.file.Path path) throws IOException {
        return new String(java.nio.file.Files.readAllBytes(path), java.nio.charset.StandardCharsets.UTF_8);
    }
    public static byte[] readStream(InputStream in) throws IOException {
        ByteArrayOutputStream b=new ByteArrayOutputStream(); byte[] chunk=new byte[4096]; int n;
        while((n=in.read(chunk))!=-1) { b.write(chunk,0,n); if(b.size()>16*1024*1024)throw new IOException("stream_too_large"); }
        return b.toByteArray();
    }
    public static String error(Throwable t)''');p.write_text(s)
# Treat partially written interrupted runs as interrupted when the user opens the app again.
p=java/'netcheck/NetCheckActivity.java';s=p.read_text();s=s.replace('super.onCreate(b);getWindow()', '''super.onCreate(b);
        if(NetRunService.instance==null) {
            for(File d:NetReport.reports(this)) try {
                File f=new File(d,"report.json"); JSONObject r=new JSONObject(NetReport.readText(f.toPath()));
                if("running".equals(r.optString("status"))) {
                    r.put("status","interrupted_process");
                    NetReport.atomic(f,r.toString(2));
                    NetReport.atomic(new File(d,"summary.txt"),NetReport.summary(r));
                }
            } catch(Exception ignored) {}
        }
        getWindow()''').replace('Files.readString(', 'NetReport.readText(');p.write_text(s)
p=root/'app/src/androidTest/java/com/emanuelef/remote_capture/netcheck/NetSmoke.java'
if p.exists():p.write_text(p.read_text().replace('z.getInputStream(e).readAllBytes()', 'NetReport.readStream(z.getInputStream(e))'))
print('Disabled persistent upstream engine logs, fixed file API compatibility and added interrupted-run recovery.')
