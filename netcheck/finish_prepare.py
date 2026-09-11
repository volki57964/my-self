#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import sys, xml.etree.ElementTree as ET
root=Path(sys.argv[1]); java=root/'app/src/main/java/com/emanuelef/remote_capture'
p=java/'PCAPdroid.java';s=p.read_text().replace('// NetCheck: avoid persistent native diagnostic logs outside explicit reports.','if(!isUnderTest())\n            Log.init(getCacheDir().getAbsolutePath());');p.write_text(s)
p=java/'Log.java';s=p.read_text().replace('cachedir + "/" + DEFAULT_LOGGER_PATH','"/dev/null"').replace('cachedir + "/" + MITM_LOGGER_PATH','"/dev/null"');p.write_text(s)
# Upstream only used this field during hostname resolution. Our per-socket network pinning needs it for the entire session.
p=java/'CaptureService.java';s=p.read_text();s=s.replace('boolean hostResolved = resolveHosts();\n        mUnderlyingNetwork = null;', 'boolean hostResolved = resolveHosts();\n        // NetCheck: retain physical Network until the capture service ends.');p.write_text(s)
p=java/'netcheck/NetReport.java';s=p.read_text().replace('public static String error(Throwable t)', '''public static String readText(java.nio.file.Path path) throws IOException {
        return new String(java.nio.file.Files.readAllBytes(path), java.nio.charset.StandardCharsets.UTF_8);
    }
    public static byte[] readStream(InputStream in) throws IOException {
        ByteArrayOutputStream b=new ByteArrayOutputStream(); byte[] chunk=new byte[4096]; int n;
        while((n=in.read(chunk))!=-1) { b.write(chunk,0,n); if(b.size()>16*1024*1024)throw new IOException("stream_too_large"); }
        return b.toByteArray();
    }
    public static String error(Throwable t)''');p.write_text(s)
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
        getWindow()''').replace('Files.readString(', 'NetReport.readText(')
s=s.replace('c.setChecked(checked);layout.addView(c);','c.setChecked(checked);c.setButtonTintList(new android.content.res.ColorStateList(new int[][]{new int[]{android.R.attr.state_checked},new int[]{}},new int[]{0xFF8AC9FC,0xFF8AA2B8}));layout.addView(c);')
s=s.replace('Возможен расход до ~50 МиБ и влияние локального VPN на соединения.', 'Лимит наблюдения — примерно 50 МиБ. Он не блокирует дальнейший трафик приложений: после завершения проверь, что видео остановлено. Локальный VPN может влиять на соединения.')
p.write_text(s)
p=root/'app/src/androidTest/java/com/emanuelef/remote_capture/netcheck/NetSmoke.java'
if p.exists():p.write_text(p.read_text().replace('z.getInputStream(e).readAllBytes()', 'NetReport.readStream(z.getInputStream(e))'))
A='{http://schemas.android.com/apk/res/android}';T='{http://schemas.android.com/tools}'
ET.register_namespace('android',A[1:-1]);ET.register_namespace('tools',T[1:-1])
p=root/'app/src/main/AndroidManifest.xml';tree=ET.parse(p);manifest=tree.getroot();app=manifest.find('application')
app.set(T+'replace','android:label,android:allowBackup')
for permission in ['QUERY_ALL_PACKAGES','WRITE_EXTERNAL_STORAGE','READ_EXTERNAL_STORAGE','READ_PHONE_STATE','RECEIVE_BOOT_COMPLETED','WRITE_CLIPS','INTERACT_ACROSS_USERS']:
    ET.SubElement(manifest,'uses-permission',{A+'name':'android.permission.'+permission,T+'node':'remove'})
ET.indent(tree,space='    ');tree.write(p,encoding='utf-8',xml_declaration=True)
p=java/'netcheck/NetRunService.java';s=p.read_text().replace('if(SystemClock.elapsedRealtime()>deadline)requestStop("time_limit");', '''if(!ownsCapture) {
                        Network current=cm.getActiveNetwork();
                        NetworkCapabilities active=cm.getNetworkCapabilities(current);
                        if(active!=null && active.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                            requestStop("external_vpn_enabled_during_run"); return;
                        }
                        if(current!=null && !current.equals(network)) {
                            requestStop("default_network_changed"); return;
                        }
                    }
                    if(SystemClock.elapsedRealtime()>deadline)requestStop("time_limit");''');p.write_text(s)
p=java/'netcheck/AutoService.java';s=p.read_text().replace('public void endStep(){target=null;handler.removeCallbacks(tick);}', '''public void endStep(){
        String previous=target;target=null;handler.removeCallbacks(tick);
        if(previous==null || NetRunService.instance==null)return;
        AccessibilityNodeInfo root=null;
        try {
            root=getRootInActiveWindow();
            if(root==null || root.getPackageName()==null || !previous.contentEquals(root.getPackageName()))return;
            if("com.google.android.youtube".equals(previous)) {
                for(String id:new String[]{"player_control_play_pause_replay_button","play_pause_button"}) {
                    for(AccessibilityNodeInfo n:root.findAccessibilityNodeInfosByViewId(previous+":id/"+id)) {
                        try {
                            String d=n.getContentDescription()==null?"":n.getContentDescription().toString().trim().toLowerCase(Locale.ROOT);
                            if((d.equals("pause")||d.equals("приостановить")||d.equals("пауза")) && n.isClickable()) n.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                        } finally { n.recycle(); }
                    }
                }
            }
            startActivity(new Intent(this,NetCheckActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP));
        } catch(Exception ignored) { } finally { if(root!=null)root.recycle(); }
    }''');p.write_text(s)
# Rely on Android's system fonts only.
res=root/'app/src/main/res'
p=res/'layout/payload_item.xml'
if p.exists():p.write_text(p.read_text().replace('@font/sourcecodepro_regular','monospace'))
font=res/'font/sourcecodepro_regular.ttf'
if font.exists():font.unlink()
p=res/'values/netcheck.xml';s=p.read_text().replace('<style name="NetCheckTheme" parent="Theme.AppCompat.DayNight.NoActionBar">','<style name="NetCheckTheme" parent="Theme.AppCompat.DayNight.NoActionBar"><item name="android:windowBackground">#0C1421</item><item name="android:windowLightNavigationBar">false</item>');p.write_text(s)
print('Applied privacy, network pinning, compatibility, readable UI and scenario finish handling.')
