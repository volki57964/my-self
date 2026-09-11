/* SPDX-License-Identifier: GPL-3.0-or-later */
package com.emanuelef.remote_capture.netcheck;

import android.app.*;
import android.content.*;
import android.net.*;
import android.os.*;
import androidx.core.content.FileProvider;
import androidx.preference.PreferenceManager;
import com.emanuelef.remote_capture.CaptureService;
import com.emanuelef.remote_capture.model.*;
import org.json.*;
import java.io.*;
import java.nio.file.Files;
import java.util.*;
import java.util.zip.*;

public final class NetSmoke extends Instrumentation {
    @Override public void onCreate(Bundle args){super.onCreate(args);start();}
    private void require(boolean ok,String message){if(!ok)throw new IllegalStateException(message);}
    @Override public void onStart(){
        Bundle out=new Bundle();Activity activity=null;
        try{
            Context c=getTargetContext();
            Intent launch=new Intent(c,NetCheckActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            activity=startActivitySync(launch);waitForIdleSync();
            require(activity!=null,"launcher_missing");
            ConnectivityManager cm=c.getSystemService(ConnectivityManager.class);Network net=cm.getActiveNetwork();require(net!=null,"emulator_network_missing");
            NetReport report=new NetReport(c,net,"AUTOMATED_EMULATOR_SMOKE_NOT_USER_MEASUREMENT",false,NetReport.obj("synthetic_export_test",true));
            report.result(NetReport.obj("target","unit-test","stage","export","status","completed"));
            report.finish("smoke_test");
            File zip=NetReport.zip(c,new File[]{report.dir});require(zip.length()>0,"empty_zip");
            try(ZipFile z=new ZipFile(zip)){
                require(z.size()==3,"wrong_zip_entry_count");
                ZipEntry e=z.getEntry(report.id+"/report.json");require(e!=null,"json_missing");
                JSONObject j=new JSONObject(new String(z.getInputStream(e).readAllBytes(),java.nio.charset.StandardCharsets.UTF_8));
                require(j.getJSONArray("results").length()==1,"json_results_lost");
            }
            Uri uri=FileProvider.getUriForFile(c,c.getPackageName()+".netcheck.files",zip);
            try(InputStream f=c.getContentResolver().openInputStream(uri)){require(f!=null && f.read()==80,"shared_zip_unreadable");}
            boolean invalid=false;try{NetProbe.validate("https://example.com/?token=private");}catch(Exception e){invalid=true;}require(invalid,"sensitive_query_not_rejected");
            CaptureSettings s=new CaptureSettings(c,PreferenceManager.getDefaultSharedPreferences(c));
            s.app_filter=new HashSet<>(Collections.singletonList(c.getPackageName()));s.dump_mode=Prefs.DumpMode.NONE;s.ip_mode=Prefs.IpMode.BOTH;s.root_capture=false;s.tls_decryption=false;s.full_payload=false;s.socks5_enabled=false;s.auto_block_private_dns=false;s.block_quic_mode=Prefs.BlockQuicMode.NEVER;s.api_capture=true;
            PreferenceManager.getDefaultSharedPreferences(c).edit().putBoolean(Prefs.PREF_USE_SYSTEM_DNS,true).putBoolean(Prefs.PREF_MALWARE_DETECTION,false).putBoolean(Prefs.PREF_FIREWALL,false).apply();
            Intent cap=new Intent(c,CaptureService.class).putExtra("settings",s);
            c.startForegroundService(cap);
            long end=SystemClock.elapsedRealtime()+12000;
            while(!CaptureService.isServiceActive()&&SystemClock.elapsedRealtime()<end)Thread.sleep(100);
            require(CaptureService.isServiceActive(),"native_capture_did_not_start");
            Thread.sleep(1200);require(!CaptureService.hasError(),"native_capture_reported_error");
            require(CaptureService.getCurPayloadMode()==Prefs.PayloadMode.NONE,"payload_collection_enabled");
            out.putString("capture_dns",CaptureService.getDNSServer());
            CaptureService.stopService();
            end=SystemClock.elapsedRealtime()+8000;
            while(CaptureService.isServiceActive()&&SystemClock.elapsedRealtime()<end)Thread.sleep(100);
            require(!CaptureService.isServiceActive(),"capture_did_not_stop");
            out.putString("stream","NETCHECK_SMOKE_OK: launcher, local JSON, ZIP export, content URI, URL validation, native VPN startup/stop; third-party apps not installed in emulator.\n");
            finish(Activity.RESULT_OK,out);
        }catch(Throwable t){out.putString("stream","NETCHECK_SMOKE_FAILED: "+NetReport.error(t)+"\n");finish(Activity.RESULT_CANCELED,out);}
        finally{
            if(CaptureService.isServiceActive())CaptureService.stopService();
            if(activity!=null){Activity a=activity;runOnMainSync(a::finish);}
        }
    }
}
