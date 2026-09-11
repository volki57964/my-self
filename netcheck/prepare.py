#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import shutil, sys, re, xml.etree.ElementTree as ET

root=Path(sys.argv[1]).resolve()
recipe=Path(__file__).resolve().parent
java=root/'app/src/main/java/com/emanuelef/remote_capture'
for f in (recipe/'overlay').glob('*.java'):
    (java/'netcheck').mkdir(parents=True,exist_ok=True)
    shutil.copy2(f,java/'netcheck'/f.name)

def replace_method(text,signature,body):
    pos=text.index(signature)
    start=text.index('{',pos)
    depth=1;end=start+1
    while depth:
        if text[end]=='{':depth+=1
        elif text[end]=='}':depth-=1
        end+=1
    return text[:start]+'{\n'+body+'\n    }'+text[end:]

p=root/'app/build.gradle'
s=p.read_text().replace('applicationId "com.emanuelef.remote_capture"','applicationId "org.netcheck.pilot"')
s=s.replace('minSdkVersion 23','minSdkVersion 29').replace('versionCode 93','versionCode 1').replace('versionName "2.0.1"','versionName "0.1"')
s=s.replace('minSdkVersion 29','minSdkVersion 29\n        testInstrumentationRunner "com.emanuelef.remote_capture.netcheck.NetSmoke"')
p.write_text(s)

p=java/'CaptureService.java';s=p.read_text()
s=replace_method(s,'public static Prefs.PayloadMode getCurPayloadMode()', '        return Prefs.PayloadMode.NONE;')
s=replace_method(s,'public boolean protect(int socket)', '''        if (mSettings.root_capture) return false;
        if (!super.protect(socket) || mUnderlyingNetwork == null) return false;
        try (android.os.ParcelFileDescriptor descriptor = android.os.ParcelFileDescriptor.fromFd(socket)) {
            mUnderlyingNetwork.bindSocket(descriptor.getFileDescriptor());
            return true;
        } catch (java.io.IOException e) {
            return false;
        }''')
s=s.replace('MainActivity.class','com.emanuelef.remote_capture.netcheck.NetCheckActivity.class')
s=s.replace('return START_STICKY;', 'return START_NOT_STICKY;')
p.write_text(s)

# Constrain the fork's native capture log: no file payload logging and no root/MITM UI entry.
p=java/'PCAPdroid.java';s=p.read_text()
s=s.replace('if(!isUnderTest())\n            Log.init(getCacheDir().getAbsolutePath());','// NetCheck: avoid persistent native diagnostic logs outside explicit reports.')
p.write_text(s)

A='{http://schemas.android.com/apk/res/android}'
ET.register_namespace('android','http://schemas.android.com/apk/res/android')
ET.register_namespace('tools','http://schemas.android.com/tools')
p=root/'app/src/main/AndroidManifest.xml';tree=ET.parse(p);manifest=tree.getroot()
remove_permissions={'android.permission.QUERY_ALL_PACKAGES','android.permission.WRITE_CLIPS','android.permission.WRITE_EXTERNAL_STORAGE','android.permission.RECEIVE_BOOT_COMPLETED','android.permission.INTERACT_ACROSS_USERS'}
for e in list(manifest):
    if e.tag.startswith('uses-permission') and e.get(A+'name') in remove_permissions:manifest.remove(e)
queries=ET.SubElement(manifest,'queries')
for pkg in ['org.telegram.messenger','org.telegram.messenger.web','com.google.android.youtube','com.zhiliaoapp.musically','com.ss.android.ugc.trill']:
    ET.SubElement(queries,'package',{A+'name':pkg})
app=manifest.find('application')
app.set(A+'label','NetCheck');app.set(A+'allowBackup','false');app.set(A+'fullBackupContent','false');app.set(A+'usesCleartextTraffic','true')
app.set(A+'icon','@drawable/netcheck_icon');app.set(A+'roundIcon','@drawable/netcheck_icon')
for e in list(app):
    name=e.get(A+'name','')
    if name in ['.BootReceiver','.VpnReconnectService','.activities.CaptureCtrl']:
        app.remove(e)
    elif e.tag=='activity':
        e.set(A+'exported','false')
        for f in list(e):
            if f.tag=='intent-filter':e.remove(f)
act=ET.SubElement(app,'activity',{A+'name':'.netcheck.NetCheckActivity',A+'exported':'true',A+'theme':'@style/NetCheckTheme'})
i=ET.SubElement(act,'intent-filter');ET.SubElement(i,'action',{A+'name':'android.intent.action.MAIN'});ET.SubElement(i,'category',{A+'name':'android.intent.category.LAUNCHER'})
svc=ET.SubElement(app,'service',{A+'name':'.netcheck.NetRunService',A+'exported':'false',A+'foregroundServiceType':'specialUse'})
ET.SubElement(svc,'property',{A+'name':'android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE',A+'value':'User initiated network diagnostics and short app traffic observation; local reports only'})
svc=ET.SubElement(app,'service',{A+'name':'.netcheck.AutoService',A+'exported':'true',A+'label':'NetCheck: автоматизация теста',A+'permission':'android.permission.BIND_ACCESSIBILITY_SERVICE'})
i=ET.SubElement(svc,'intent-filter');ET.SubElement(i,'action',{A+'name':'android.accessibilityservice.AccessibilityService'})
ET.SubElement(svc,'meta-data',{A+'name':'android.accessibilityservice',A+'resource':'@xml/netcheck_accessibility'})
provider=ET.SubElement(app,'provider',{A+'name':'androidx.core.content.FileProvider',A+'authorities':'${applicationId}.netcheck.files',A+'exported':'false',A+'grantUriPermissions':'true'})
ET.SubElement(provider,'meta-data',{A+'name':'android.support.FILE_PROVIDER_PATHS',A+'resource':'@xml/netcheck_paths'})
ET.indent(tree,space='    ');tree.write(p,encoding='utf-8',xml_declaration=True)
res=root/'app/src/main/res'
resources={
'xml/netcheck_paths.xml':'''<paths xmlns:android="http://schemas.android.com/apk/res/android"><cache-path name="reports" path="netcheck-export/" /></paths>''',
'xml/netcheck_accessibility.xml':'''<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
 android:accessibilityEventTypes="typeWindowStateChanged|typeWindowContentChanged"
 android:accessibilityFeedbackType="feedbackGeneric"
 android:accessibilityFlags="flagReportViewIds"
 android:canRetrieveWindowContent="true"
 android:canPerformGestures="false"
 android:isAccessibilityTool="false"
 android:notificationTimeout="200"
 android:description="@string/netcheck_accessibility_description"
 android:packageNames="org.telegram.messenger,org.telegram.messenger.web,com.google.android.youtube,com.zhiliaoapp.musically,com.ss.android.ugc.trill" />''',
'values/netcheck.xml':'''<resources>
 <string name="netcheck_accessibility_description">Только во время подтверждённого теста открывает выбранные приложения и пробует нажать известную кнопку воспроизведения YouTube. Не отправляет сообщения, не записывает экран, текст переписки или пароли. Можно выключить после теста.</string>
 <style name="NetCheckTheme" parent="Theme.AppCompat.DayNight.NoActionBar"><item name="android:fontFamily">sans</item><item name="android:windowLightStatusBar">false</item><item name="android:navigationBarColor">#0C1421</item><item name="colorAccent">#8AC9FC</item></style>
 </resources>''',
'drawable/netcheck_icon.xml':'''<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108"><path android:fillColor="#0C1421" android:pathData="M0,0h108v108h-108z"/><path android:fillColor="#8AC9FC" android:pathData="M28,74v-40h9l25,25v-25h12v40h-9l-25,-25v25z"/><path android:fillColor="#51DBBC" android:pathData="M73,20a7,7 0,1 0,0.1 0z"/></vector>'''
}
for name,content in resources.items():
    f=res/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(content)

# Patch small privacy and robustness details in our overlay after copying.
p=java/'netcheck/NetCheckActivity.java';s=p.read_text()
s=s.replace('setContentView(scroll);','setContentView(scroll);\n        scroll.setOnApplyWindowInsetsListener((v,insets)->{ v.setPadding(0,insets.getSystemWindowInsetTop(),0,insets.getSystemWindowInsetBottom()); return insets; });')
p.write_text(s)
p=java/'netcheck/NetProbe.java';s=p.read_text()
s=s.replace('ips.addAll(dns(u.getHost(),DnsResolver.TYPE_A));\n                if(!stopped())ips.addAll(dns(u.getHost(),DnsResolver.TYPE_AAAA));','''String host=u.getHost().replace("[", "").replace("]", "");
                if(android.net.InetAddresses.isNumericAddress(host)) {
                    ips.add(android.net.InetAddresses.parseNumericAddress(host));
                    report.result(NetReport.obj("target",host,"stage","DNS","status","skipped","reason","literal_ip_does_not_need_dns"));
                } else {
                    ips.addAll(dns(host,DnsResolver.TYPE_A));
                    if(!stopped())ips.addAll(dns(host,DnsResolver.TYPE_AAAA));
                }''')
s=s.replace('!u.getHost().matches("[0-9.:]+")','!android.net.InetAddresses.isNumericAddress(u.getHost().replace("[", "").replace("]", ""))')
p.write_text(s)

# Instrumentation tests are not included in the shipped main APK.
tests=root/'app/src/androidTest/java/com/emanuelef/remote_capture/netcheck'
tests.mkdir(parents=True,exist_ok=True)
if (recipe/'NetSmoke.java').exists():shutil.copy2(recipe/'NetSmoke.java',tests/'NetSmoke.java')
print('NetCheck overlay integrated with pinned upstream; no user records included.')
