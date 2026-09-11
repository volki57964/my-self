/* SPDX-License-Identifier: GPL-3.0-or-later */
package com.emanuelef.remote_capture.netcheck;

import android.app.*;
import android.content.*;
import android.net.*;
import android.os.*;
import androidx.core.content.FileProvider;
import androidx.preference.PreferenceManager;
import com.emanuelef.remote_capture.CaptureService;
import com.emanuelef.remote_capture.ConnectionsRegister;
import com.emanuelef.remote_capture.model.*;
import org.json.*;
import java.io.*;
import java.net.*;
import java.util.*;
import java.util.zip.*;

public final class NetSmoke extends Instrumentation {
    @Override public void onCreate(Bundle args){super.onCreate(args);start();}
    private void require(boolean ok,String message){if(!ok)throw new IllegalStateException(message);}
    private void echo(Network network) throws Exception {
        byte[] data="NETCHECK_CONTROL_PAYLOAD_123456789".getBytes(java.nio.charset.StandardCharsets.US_ASCII);
        try(Socket s=network==null?new Socket():network.getSocketFactory().createSocket()) {
            s.connect(new InetSocketAddress("10.0.2.2",18443),5000);s.setSoTimeout(5000);s.getOutputStream().write(data);s.getOutputStream().flush();
            byte[] reply=new byte[data.length];new DataInputStream(s.getInputStream()).readFully(reply);require(Arrays.equals(data,reply),"tcp_echo_corrupted");Thread.sleep(150);
        }
        try(DatagramSocket s=new DatagramSocket()) {
            if(network!=null)network.bindSocket(s);
            s.setSoTimeout(5000);InetAddress host=InetAddress.getByName("10.0.2.2");s.connect(host,18444);
            s.send(new DatagramPacket(data,data.length,host,18444));byte[] b=new byte[1024];DatagramPacket packet=new DatagramPacket(b,b.length);s.receive(packet);
            require(Arrays.equals(data,Arrays.copyOf(b,packet.getLength())),"udp_echo_corrupted");Thread.sleep(150);
        }
    }
    @Override public void onStart(){
        Bundle out=new Bundle();Activity activity=null;
        try{
            Context c=getTargetContext();
            activity=startActivitySync(new Intent(c,NetCheckActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));waitForIdleSync();
            require(activity!=null,"launcher_missing");
            ConnectivityManager cm=c.getSystemService(ConnectivityManager.class);Network net=cm.getActiveNetwork();require(net!=null,"emulator_network_missing");
            echo(net);
            NetReport report=new NetReport(c,net,"CONTROLLED_EMULATOR_TEST_NOT_USER_DATA",false,NetReport.obj("controlled_ci_test",true));
            NetProbe probe=new NetProbe(net,report,new NetProbe.Gate(){public boolean stopped(){return false;}public void progress(String s){}});
            probe.run(Arrays.asList("http://10.0.2.2/","https://10.0.2.2/"),false);probe.close();
            JSONArray observations=report.root.getJSONArray("results");boolean httpOK=false,certRejected=false;
            for(int i=0;i<observations.length();i++) {
                JSONObject r=observations.getJSONObject(i);
                if("HTTP".equals(r.optString("stage")) && r.optInt("http_code")==200 && r.optInt("body_bytes")>0)httpOK=true;
                if("TLS".equals(r.optString("stage")) && "failed".equals(r.optString("status")) && r.optString("failure").contains("SSLHandshakeException"))certRejected=true;
            }
            require(httpOK,"controlled_http_probe_failed");require(certRejected,"self_signed_certificate_not_rejected_as_expected");
            report.finish("smoke_test");
            File zip=NetReport.zip(c,new File[]{report.dir});require(zip.length()>0,"empty_zip");
            try(ZipFile z=new ZipFile(zip)){
                require(z.size()==3,"wrong_zip_entry_count");ZipEntry e=z.getEntry(report.id+"/report.json");require(e!=null,"json_missing");
                JSONObject j=new JSONObject(new String(NetReport.readStream(z.getInputStream(e)),java.nio.charset.StandardCharsets.UTF_8));
                require(j.getJSONArray("results").length()>=4,"json_results_lost");
            }
            Uri uri=FileProvider.getUriForFile(c,c.getPackageName()+".netcheck.files",zip);
            try(InputStream f=c.getContentResolver().openInputStream(uri)){require(f!=null && f.read()==80,"shared_zip_unreadable");}
            boolean invalid=false;try{NetProbe.validate("https://example.com/?token=private");}catch(Exception e){invalid=true;}require(invalid,"sensitive_query_not_rejected");
            CaptureSettings s=new CaptureSettings(c,PreferenceManager.getDefaultSharedPreferences(c));
            s.app_filter=new HashSet<>(Collections.singletonList(c.getPackageName()));s.dump_mode=Prefs.DumpMode.NONE;s.ip_mode=Prefs.IpMode.BOTH;s.root_capture=false;s.tls_decryption=false;s.full_payload=false;s.socks5_enabled=false;s.auto_block_private_dns=false;s.block_quic_mode=Prefs.BlockQuicMode.NEVER;s.api_capture=true;
            PreferenceManager.getDefaultSharedPreferences(c).edit().putBoolean(Prefs.PREF_USE_SYSTEM_DNS,true).putBoolean(Prefs.PREF_MALWARE_DETECTION,false).putBoolean(Prefs.PREF_FIREWALL,false).apply();
            c.startForegroundService(new Intent(c,CaptureService.class).putExtra("settings",s));
            long end=SystemClock.elapsedRealtime()+12000;
            while(!CaptureService.isServiceActive()&&SystemClock.elapsedRealtime()<end)Thread.sleep(100);
            require(CaptureService.isServiceActive(),"native_capture_did_not_start");
            Network vpn=null;
            end=SystemClock.elapsedRealtime()+12000;
            while(vpn==null && SystemClock.elapsedRealtime()<end){
                for(Network n:cm.getAllNetworks()){NetworkCapabilities nc=cm.getNetworkCapabilities(n);if(nc!=null&&nc.hasTransport(NetworkCapabilities.TRANSPORT_VPN)){vpn=n;break;}}
                if(vpn==null)Thread.sleep(100);
            }
            require(vpn!=null,"vpn_network_not_registered");
            Thread.sleep(500);require(!CaptureService.hasError(),"native_capture_reported_error");
            require(CaptureService.getCurPayloadMode()==Prefs.PayloadMode.NONE,"payload_collection_enabled");
            echo(vpn);
            ConnectionsRegister reg=CaptureService.getConnsRegister();require(reg!=null,"capture_register_missing");
            boolean tcp=false,udp=false;String details="";
            end=SystemClock.elapsedRealtime()+6000;
            while(!(tcp&&udp)&&SystemClock.elapsedRealtime()<end){
                Thread.sleep(250);StringBuilder b=new StringBuilder();
                synchronized(reg){for(int i=0;i<reg.getConnCount();i++){ConnectionDescriptor d=reg.getConn(i);if(d==null)continue;b.append(d.dst_ip).append(':').append(d.dst_port).append('/').append(d.ipproto).append(" rx=").append(d.rcvd_bytes).append(" uid=").append(d.uid).append(';');if("10.0.2.2".equals(d.dst_ip) && d.rcvd_bytes>0){if(d.ipproto==6 && d.dst_port==18443)tcp=true;if(d.ipproto==17 && d.dst_port==18444)udp=true;}}}
                details=b.toString();
            }
            require(tcp,"tcp_flow_not_observed: "+details);require(udp,"udp_flow_not_observed: "+details);
            out.putString("capture_dns",CaptureService.getDNSServer());CaptureService.stopService();
            end=SystemClock.elapsedRealtime()+8000;while(CaptureService.isServiceActive()&&SystemClock.elapsedRealtime()<end)Thread.sleep(100);
            require(!CaptureService.isServiceActive(),"capture_did_not_stop");
            out.putString("stream","NETCHECK_SMOKE_OK: launcher; controlled HTTP; self-signed TLS rejection; verified TCP and UDP round trips before/through capture; metadata present; local JSON/ZIP/content URI; capture stop. Third-party app UI and Russian networks not tested.\n");
            finish(Activity.RESULT_OK,out);
        }catch(Throwable t){out.putString("stream","NETCHECK_SMOKE_FAILED: "+NetReport.error(t)+"\n");finish(Activity.RESULT_CANCELED,out);}
        finally{if(CaptureService.isServiceActive())CaptureService.stopService();if(activity!=null){Activity a=activity;runOnMainSync(a::finish);}}
    }
}
